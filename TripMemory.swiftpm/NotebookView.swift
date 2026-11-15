import SwiftUI
import PhotosUI
import PencilKit
import CoreLocation

// ノートの色
enum NoteInk {
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let ink = Color(red: 0.23, green: 0.23, blue: 0.21)
    static let ink2 = Color(red: 0.42, green: 0.40, blue: 0.37)
    static let red = Color(red: 0.84, green: 0.20, blue: 0.17)
    static let tape = Color(red: 0.94, green: 0.84, blue: 0.47).opacity(0.7)
}

// 編集画面に渡す写真
struct EditTarget: Identifiable {
    let id = UUID()
    let photoID: UUID
    let data: Data
}

// 手書きのペンの種類
enum PenChoice: String, CaseIterable {
    case black, red, blue, marker, eraser

    var name: String {
        switch self {
        case .black: return "黒"
        case .red: return "赤"
        case .blue: return "青"
        case .marker: return "蛍光ペン"
        case .eraser: return "消しゴム"
        }
    }

    var icon: String {
        switch self {
        case .eraser: return "eraser"
        case .marker: return "highlighter"
        default: return "pencil.tip"
        }
    }

    var swatch: Color {
        switch self {
        case .black: return .black
        case .red: return Color(red: 0.84, green: 0.2, blue: 0.17)
        case .blue: return Color(red: 0.18, green: 0.37, blue: 0.66)
        case .marker: return .yellow
        case .eraser: return .gray
        }
    }

    var pkTool: PKTool {
        switch self {
        case .black: return PKInkingTool(.pen, color: .black, width: 4)
        case .red: return PKInkingTool(.pen, color: UIColor(red: 0.84, green: 0.2, blue: 0.17, alpha: 1), width: 4)
        case .blue: return PKInkingTool(.pen, color: UIColor(red: 0.18, green: 0.37, blue: 0.66, alpha: 1), width: 4)
        case .marker: return PKInkingTool(.marker, color: UIColor.systemYellow, width: 18)
        case .eraser: return PKEraserTool(.vector)
        }
    }
}

// MARK: - 旅ノートの画面

struct NotebookView: View {
    let tripID: UUID
    let onClose: () -> Void

    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var maps = MapStore.shared

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var adding = false
    @State private var selectedID: UUID?
    @State private var editTarget: EditTarget?
    @State private var removing: TripPhoto?
    @State private var penMode = false
    @State private var pen: PenChoice = .black
    @State private var drawing = PKDrawing()
    @State private var drawingLoaded = false
    @State private var undoTick = 0
    @State private var spreadSize: CGSize = .zero
    @State private var exported: RenderResult?

    var trip: Trip? { store.trip(tripID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if penMode { penBar }
            GeometryReader { geo in
                if let trip {
                    spread(trip: trip, size: geo.size)
                        .onAppear { spreadSize = geo.size }
                        .onChange(of: geo.size) { _, s in spreadSize = s }
                }
            }
            .padding(16)
        }
        .foregroundStyle(.white)
        .background(Color(white: 0.16).ignoresSafeArea())
        .task {
            loadDrawing()
            await maps.loadIfNeeded()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPhotos(items) }
        }
        .onChange(of: drawing) { _, d in
            if drawingLoaded { saveDrawing(d) }
        }
        .fullScreenCover(item: $editTarget) { t in
            ContentView(initialData: t.data, closeTitle: "ノートに戻る",
                        onClose: { editTarget = nil },
                        onSaveToNote: { image in
                            store.saveEdited(image, photoID: t.photoID, tripID: tripID)
                        })
        }
        .fullScreenCover(item: $exported) { r in
            ResultView(result: r, editTitle: "ノートに戻る")
        }
        .confirmationDialog("この写真をノートから外しますか？",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("外す", role: .destructive) {
                if let p = removing {
                    store.removePhoto(p, from: tripID)
                    selectedID = nil
                }
                removing = nil
            }
            Button("やめる", role: .cancel) { removing = nil }
        } message: {
            Text("写真アプリの元の写真は消えません。")
        }
    }

    // 上のボタン列
    var header: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                Label("本棚", systemImage: "chevron.backward")
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 2) {
                Text(trip?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if adding || maps.lines.isEmpty {
                ProgressView().tint(.white)
            }

            PhotosPicker(selection: $pickerItems, maxSelectionCount: 30, matching: .images) {
                Label("写真を追加", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(adding)

            Button {
                penMode.toggle()
                selectedID = nil
            } label: {
                Label(penMode ? "ペンを終わる" : "ペン", systemImage: "pencil.tip")
            }
            .buttonStyle(.bordered)
            .tint(penMode ? .orange : nil)

            Button {
                exportImage()
            } label: {
                Label("画像で書き出し", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.09))
    }

    var subtitle: String {
        guard let trip else { return "" }
        var parts: [String] = []
        if !trip.dateRangeText.isEmpty { parts.append(trip.dateRangeText) }
        parts.append("写真 \(trip.photos.count)枚")
        if !trip.prefectures.isEmpty { parts.append("\(trip.prefectures.count)県") }
        return parts.joined(separator: "　・　")
    }

    // ペンを選ぶ列
    var penBar: some View {
        HStack(spacing: 10) {
            ForEach(PenChoice.allCases, id: \.self) { choice in
                Button {
                    pen = choice
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(choice.swatch).frame(width: 14, height: 14)
                        Text(choice.name)
                    }
                }
                .buttonStyle(.bordered)
                .tint(pen == choice ? .orange : nil)
            }
            Button {
                undoTick += 1
            } label: {
                Label("1つ戻す", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            Spacer()
            Text("指でも書けます")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.12))
    }

    // 見開きのページ
    func spread(trip: Trip, size: CGSize) -> some View {
        let rects = NotebookPages.rects(for: size)
        return ZStack(alignment: .topLeading) {
            NotebookPages(trip: trip, lines: maps.lines, size: size, selectedID: selectedID,
                          editable: !penMode,
                          onTapPhoto: { p in selectedID = p.id },
                          onMovePhoto: { id, point in
                              store.update(tripID) { t in
                                  if let i = t.photos.firstIndex(where: { $0.id == id }) {
                                      t.photos[i].x = point.x
                                      t.photos[i].y = point.y
                                  }
                              }
                          })

            // 手書きメモ（ペンのときだけ書ける）
            DrawingCanvas(drawing: $drawing, isActive: penMode, tool: pen.pkTool, undoTick: undoTick)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(penMode)

            // タッチした写真を大きく
            if let id = selectedID, let index = trip.photos.firstIndex(where: { $0.id == id }) {
                let photo = trip.photos[index]
                EnlargedPhoto(image: store.thumbnail(tripID, photo), number: index + 1, photo: photo,
                              onEdit: {
                                  if let data = store.originalData(tripID, photo) {
                                      editTarget = EditTarget(photoID: photo.id, data: data)
                                  }
                              },
                              onRemove: { removing = photo },
                              onRevert: photo.edited == true ? {
                                  store.revertEdited(photoID: photo.id, tripID: tripID)
                              } : nil,
                              onClose: { selectedID = nil })
                    .frame(width: rects.photos.width, height: rects.photos.height)
                    .offset(x: rects.photos.minX, y: rects.photos.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 写真の追加・手書き・書き出し

    func addPhotos(_ items: [PhotosPickerItem]) async {
        adding = true
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await store.addPhoto(data: data, to: tripID)
            }
        }
        pickerItems = []
        adding = false
    }

    var drawingURL: URL {
        store.folder(tripID).appendingPathComponent("drawing.data")
    }

    func loadDrawing() {
        if let data = try? Data(contentsOf: drawingURL), let d = try? PKDrawing(data: data) {
            drawing = d
        }
        drawingLoaded = true
    }

    func saveDrawing(_ d: PKDrawing) {
        try? d.dataRepresentation().write(to: drawingURL)
    }

    // 見開きを1枚の画像にする（手書きメモも重ねる）
    @MainActor
    func exportImage() {
        guard let trip, spreadSize.width > 0, spreadSize.height > 0 else { return }
        let size = spreadSize
        let pages = NotebookPages(trip: trip, lines: maps.lines, size: size, selectedID: nil, editable: false)
        let renderer = ImageRenderer(content: pages.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let base = renderer.uiImage else { return }

        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: CGRect(origin: .zero, size: size), scale: 2)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpg = image.jpegData(compressionQuality: 0.9) else { return }
        exported = RenderResult(image: image, jpeg: JPEGFile(data: jpg))
    }
}

// MARK: - 見開き（地図のページ＋写真のページ）

struct NotebookPages: View {
    let trip: Trip
    let lines: [MapLine]
    let size: CGSize
    var selectedID: UUID? = nil
    var editable = false
    var onTapPhoto: ((TripPhoto) -> Void)? = nil
    var onMovePhoto: ((UUID, CGPoint) -> Void)? = nil

    // 横向きなら左右、縦向きなら上下に分ける
    static func rects(for size: CGSize) -> (map: CGRect, photos: CGRect) {
        if size.width >= size.height {
            return (CGRect(x: 0, y: 0, width: size.width / 2, height: size.height),
                    CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        }
        return (CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.45),
                CGRect(x: 0, y: size.height * 0.45, width: size.width, height: size.height * 0.55))
    }

    var body: some View {
        let rects = Self.rects(for: size)
        let landscape = size.width >= size.height
        ZStack(alignment: .topLeading) {
            NotebookPaper()
                .frame(width: size.width, height: size.height)

            MapPage(trip: trip, lines: lines, selectedID: selectedID, size: rects.map.size)
                .frame(width: rects.map.width, height: rects.map.height)
                .offset(x: rects.map.minX, y: rects.map.minY)

            // ページの境目
            Rectangle()
                .fill(Color.black.opacity(0.15))
                .frame(width: landscape ? 2 : size.width, height: landscape ? size.height : 2)
                .offset(x: landscape ? rects.map.maxX - 1 : 0, y: landscape ? 0 : rects.map.maxY - 1)

            PhotosPage(trip: trip, size: rects.photos.size, editable: editable,
                       onTap: onTapPhoto, onMove: onMovePhoto)
                .frame(width: rects.photos.width, height: rects.photos.height)
                .offset(x: rects.photos.minX, y: rects.photos.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(NoteInk.paper)
    }
}

// 方眼の紙
struct NotebookPaper: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let step: CGFloat = 24
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.stroke(path, with: .color(Color(red: 0.27, green: 0.43, blue: 0.59).opacity(0.13)), lineWidth: 1)
        }
        .background(NoteInk.paper)
    }
}

// MARK: - 地図のページ

struct MapPage: View {
    let trip: Trip
    let lines: [MapLine]
    let selectedID: UUID?
    let size: CGSize

    var body: some View {
        let cardW = size.width * 0.8
        let cardH = size.height * 0.7
        let center = CGPoint(x: size.width / 2, y: size.height * 0.57)
        let hasPlaces = trip.photos.contains { $0.coordinate != nil }

        ZStack(alignment: .topLeading) {
            Color.clear

            VStack(alignment: .leading, spacing: 4) {
                Text("旅の地図")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(NoteInk.ink)
                if !trip.prefectures.isEmpty {
                    Text(trip.prefectures.map(Trip.shortPrefecture).joined(separator: "・"))
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(NoteInk.ink2)
                }
            }
            .padding(.leading, 28)
            .padding(.top, 18)

            if hasPlaces {
                // 地図を貼った紙
                VisitedMap(lines: lines, photos: trip.photos, selectedID: selectedID)
                    .frame(width: cardW, height: cardH)
                    .background(Color(white: 0.995))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .rotationEffect(.degrees(-1.2))
                    .position(center)

                // マスキングテープ
                Rectangle()
                    .fill(NoteInk.tape)
                    .frame(width: 90, height: 26)
                    .rotationEffect(.degrees(4))
                    .position(x: center.x, y: center.y - cardH / 2)

                if lines.isEmpty {
                    Text("地図を読み込み中…")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(NoteInk.ink2)
                        .position(center)
                }
            } else {
                Text("位置情報のある写真を入れると、\n行った県の地図がここに貼られます")
                    .font(.system(size: 17, design: .rounded))
                    .foregroundStyle(NoteInk.ink2)
                    .multilineTextAlignment(.center)
                    .position(center)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// 行った県だけを描いた地図（写真の番号の点と「ココ!」も描く）
struct VisitedMap: View {
    let lines: [MapLine]
    let photos: [TripPhoto]
    let selectedID: UUID?

    static let fills: [Color] = [
        Color(red: 0.96, green: 0.89, blue: 0.78),
        Color(red: 0.86, green: 0.91, blue: 0.95),
        Color(red: 0.88, green: 0.93, blue: 0.83),
        Color(red: 0.95, green: 0.86, blue: 0.88),
        Color(red: 0.91, green: 0.88, blue: 0.95)
    ]

    var body: some View {
        Canvas { ctx, size in
            Self.render(&ctx, size: size, lines: lines, photos: photos, selectedID: selectedID)
        }
    }

    static func render(_ ctx: inout GraphicsContext, size: CGSize, lines: [MapLine],
                       photos: [TripPhoto], selectedID: UUID?) {
        guard !lines.isEmpty else { return }

        // 写真のある県（貼った順）
        var groups: [Int] = []
        for p in photos {
            if let c = p.coordinate, let g = MapData.prefectureGroup(at: c, lines: lines), !groups.contains(g) {
                groups.append(g)
            }
        }
        guard !groups.isEmpty else { return }

        // 県の範囲
        var box: CGRect?
        var groupBoxes: [Int: CGRect] = [:]
        for line in lines where groups.contains(line.group) {
            let b = CGRect(x: line.minX, y: line.minY, width: line.maxX - line.minX, height: line.maxY - line.minY)
            box = box?.union(b) ?? b
            groupBoxes[line.group] = groupBoxes[line.group]?.union(b) ?? b
        }
        guard var area = box else { return }
        area = area.insetBy(dx: -area.width * 0.04, dy: -area.height * 0.04)

        let cosLat = CGFloat(cos(Double(area.midY) * .pi / 180))
        let pad: CGFloat = 22
        let wDeg = max(area.width * cosLat, 0.0001), hDeg = max(area.height, 0.0001)
        let scale = min((size.width - pad * 2) / wDeg, (size.height - pad * 2) / hDeg)
        let ox = (size.width - wDeg * scale) / 2
        let oy = (size.height - hDeg * scale) / 2
        func pt(_ lon: CGFloat, _ lat: CGFloat) -> CGPoint {
            CGPoint(x: ox + (lon - area.minX) * cosLat * scale, y: oy + (area.maxY - lat) * scale)
        }
        func ring(_ line: MapLine) -> Path {
            var path = Path()
            for (i, p) in line.points.enumerated() {
                let q = pt(p.x, p.y)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            path.closeSubpath()
            return path
        }

        // 県（塗り＋輪郭）
        for (gi, g) in groups.enumerated() {
            var path = Path()
            for line in lines where line.group == g {
                path.addPath(ring(line))
            }
            ctx.fill(path, with: .color(fills[gi % fills.count]), style: FillStyle(eoFill: true))
            ctx.stroke(path, with: .color(NoteInk.ink), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }

        // その県の中の湖
        for line in lines where line.isLake {
            let c = CLLocationCoordinate2D(latitude: Double((line.minY + line.maxY) / 2),
                                           longitude: Double((line.minX + line.maxX) / 2))
            guard area.contains(CGPoint(x: c.longitude, y: c.latitude)),
                  let g = MapData.prefectureGroup(at: c, lines: lines), groups.contains(g) else { continue }
            let path = ring(line)
            ctx.fill(path, with: .color(Color(white: 0.995)))
            ctx.stroke(path, with: .color(NoteInk.ink), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }

        // 県の名前
        var named: Set<Int> = []
        for p in photos where !p.prefecture.isEmpty {
            guard let c = p.coordinate, let g = MapData.prefectureGroup(at: c, lines: lines),
                  !named.contains(g), let gb = groupBoxes[g] else { continue }
            named.insert(g)
            let q = pt(gb.midX, gb.midY)
            ctx.draw(Text(Trip.shortPrefecture(p.prefecture))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(NoteInk.ink2),
                     at: CGPoint(x: q.x, y: q.y + 28))
        }

        // 写真の番号の点
        var selectedPoint: CGPoint?
        for (i, p) in photos.enumerated() {
            guard let c = p.coordinate else { continue }
            let q = pt(CGFloat(c.longitude), CGFloat(c.latitude))
            let isSelected = p.id == selectedID
            let r: CGFloat = isSelected ? 13 : 10
            if isSelected {
                selectedPoint = q
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - r - 3, y: q.y - r - 3, width: (r + 3) * 2, height: (r + 3) * 2)),
                         with: .color(.white))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(red: 0.89, green: 0.29, blue: 0.29)))
            ctx.draw(Text("\(i + 1)")
                        .font(.system(size: r * 1.05, weight: .bold, design: .rounded))
                        .foregroundColor(.white),
                     at: q)
        }

        // タッチした写真の場所に「ココ!」
        if let q = selectedPoint, let img = HandwritingAssets.koko, img.size.height > 0 {
            let h = min(size.width, size.height) * 0.1
            let w = h * img.size.width / img.size.height
            var lx = q.x - w - h * 0.9
            var ly = q.y - h * 2.4
            if lx < 8 { lx = q.x + h * 0.9 }
            lx = min(max(8, lx), size.width - w - 8)
            ly = min(max(8, ly), size.height - h - 8)
            let rect = CGRect(x: lx, y: ly, width: w, height: h)
            if let arrow = HereArrow.path(from: rect, to: q, dotRadius: 6, width: h * 0.09) {
                ctx.stroke(Path(arrow), with: .color(NoteInk.red),
                           style: StrokeStyle(lineWidth: h * 0.09, lineCap: .round, lineJoin: .round))
            }
            var resolved = ctx.resolve(Image(uiImage: img).renderingMode(.template))
            resolved.shading = .color(NoteInk.red)
            ctx.draw(resolved, in: rect)
        }
    }
}

// MARK: - 写真のページ

struct PhotosPage: View {
    let trip: Trip
    let size: CGSize
    let editable: Bool
    let onTap: ((TripPhoto) -> Void)?
    let onMove: ((UUID, CGPoint) -> Void)?

    @State private var dragID: UUID?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        let cardW = max(120, min(size.width * 0.4, size.height * 0.42, 240))
        ZStack(alignment: .topLeading) {
            Color.clear

            if trip.photos.isEmpty {
                Text("右上の「写真を追加」から、\n旅の写真を入れてください")
                    .font(.system(size: 17, design: .rounded))
                    .foregroundStyle(NoteInk.ink2)
                    .multilineTextAlignment(.center)
                    .position(x: size.width / 2, y: size.height / 2)
            }

            ForEach(Array(trip.photos.enumerated()), id: \.element.id) { index, photo in
                let offset = dragID == photo.id ? dragOffset : .zero
                PolaroidCard(image: TripStore.shared.thumbnail(trip.id, photo),
                             caption: caption(photo, number: index + 1),
                             width: cardW)
                    .rotationEffect(.degrees(photo.rotation))
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?(photo) }
                    .gesture(
                        DragGesture(minimumDistance: 6, coordinateSpace: .global)
                            .onChanged { v in
                                dragID = photo.id
                                dragOffset = v.translation
                            }
                            .onEnded { v in
                                let nx = min(0.95, max(0.05, photo.x + v.translation.width / size.width))
                                let ny = min(0.95, max(0.05, photo.y + v.translation.height / size.height))
                                dragID = nil
                                dragOffset = .zero
                                onMove?(photo.id, CGPoint(x: nx, y: ny))
                            }
                    )
                    .allowsHitTesting(editable)
                    .zIndex(dragID == photo.id ? 1 : 0)
                    .position(x: photo.x * size.width + offset.width, y: photo.y * size.height + offset.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    func caption(_ p: TripPhoto, number: Int) -> String {
        var parts = [Trip.circled(number)]
        if let d = p.taken {
            let f = DateFormatter()
            f.dateFormat = "M/d"
            parts.append(f.string(from: d))
        }
        if !p.prefecture.isEmpty { parts.append(Trip.shortPrefecture(p.prefecture)) }
        return parts.joined(separator: " ")
    }
}

// ポラロイド風の写真カード
struct PolaroidCard: View {
    let image: UIImage?
    let caption: String
    let width: CGFloat

    var body: some View {
        let inner = width - 20
        VStack(spacing: 6) {
            ZStack {
                Color(white: 0.85)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: inner, height: inner)
            .clipped()
            Text(caption)
                .font(.system(size: max(12, width * 0.075), weight: .medium, design: .rounded))
                .foregroundStyle(NoteInk.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: inner, alignment: .leading)
        }
        .padding(.top, 10)
        .padding(.horizontal, 10)
        .padding(.bottom, 9)
        .background(Color.white)
        .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
    }
}

// タッチした写真を大きく見せる
struct EnlargedPhoto: View {
    let image: UIImage?
    let number: Int
    let photo: TripPhoto
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onRevert: (() -> Void)?
    let onClose: () -> Void

    var dateText: String {
        guard let d = photo.taken else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd H:mm"
        return f.string(from: d)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Color(white: 0.9)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(alignment: .firstTextBaseline) {
                    Text("\(Trip.circled(number)) \(photo.prefecture)")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                    Spacer()
                    Text(dateText)
                        .font(.callout)
                        .foregroundStyle(NoteInk.ink2)
                }
                .foregroundStyle(NoteInk.ink)

                HStack(spacing: 10) {
                    Button {
                        onEdit()
                    } label: {
                        Label(photo.edited == true ? "作り直す" : "地図付きの画像を作る", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if let onRevert {
                        Button {
                            onRevert()
                        } label: {
                            Label("加工前に戻す", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Label("外す", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onClose()
                    } label: {
                        Text("閉じる")
                    }
                    .buttonStyle(.bordered)
                    .tint(NoteInk.ink)
                }
                .controlSize(.large)
            }
            .padding(18)
            .background(Color.white)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .padding(24)
        }
    }
}

// MARK: - 手書きメモ（PencilKit）

struct DrawingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var isActive: Bool
    var tool: PKTool
    var undoTick: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.drawingPolicy = .anyInput           // 指でもペンでも書ける
        view.overrideUserInterfaceStyle = .light // 黒いペンが白に変わらないように
        view.isScrollEnabled = false
        view.drawing = drawing
        view.tool = tool
        view.delegate = context.coordinator
        context.coordinator.lastUndoTick = undoTick
        return view
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        view.isUserInteractionEnabled = isActive
        view.tool = tool
        if view.drawing != drawing {
            view.drawing = drawing
        }
        if undoTick != context.coordinator.lastUndoTick {
            context.coordinator.lastUndoTick = undoTick
            view.undoManager?.undo()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas
        var lastUndoTick = 0

        init(_ parent: DrawingCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if parent.drawing != canvasView.drawing {
                parent.drawing = canvasView.drawing
            }
        }
    }
}
