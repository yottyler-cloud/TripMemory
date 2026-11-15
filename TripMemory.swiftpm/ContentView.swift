import SwiftUI
import PhotosUI
import CoreLocation

struct ContentView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var info: PhotoInfo?
    @State private var place = ""
    @State private var layout = OverlayLayout()
    @State private var mapLines: [MapLine] = []
    @State private var message = ""
    @State private var loading = false
    @State private var result: RenderResult?
    @State private var moveMapContent = false    // true: 地図の中身を動かす / false: 枠を動かす
    @State private var selectedText: TextKind = .place   // 設定を変える文字のかたまり
    @ObservedObject private var fonts = FontStore.shared

    let panelWidth: CGFloat = 330

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let info {
                // 左：写真　右：設定
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        EditorView(info: info, place: place, mapLines: mapLines,
                                   moveMapContent: moveMapContent, fontsReady: fonts.registeredNames.count,
                                   selectedText: $selectedText, layout: $layout)
                            .padding(12)
                        if !message.isEmpty || !fonts.errorMessage.isEmpty {
                            Text(fonts.errorMessage.isEmpty ? message : fonts.errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .padding(8)
                        }
                    }
                    Divider()
                    sidePanel(hasMap: info.coordinate != nil)
                        .frame(width: panelWidth)
                        .background(Color(white: 0.11))
                }
            } else {
                startScreen
            }

            if loading || !fonts.loading.isEmpty {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            do {
                mapLines = try await MapData.load()
            } catch {
                message = "地図データを読み込めませんでした。通信状態を確認してください。"
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .fullScreenCover(item: $result) { r in
            ResultView(result: r)
        }
    }

    // 最初の画面
    var startScreen: some View {
        VStack(spacing: 24) {
            Text("TripMemory")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("写真を選ぶ", systemImage: "photo")
                    .font(.title3.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            if !message.isEmpty {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
            Text("v\(appVersion)").font(.caption).foregroundStyle(.gray)
        }
    }

    // MARK: - 右側の設定一覧

    func sidePanel(hasMap: Bool) -> some View {
        VStack(spacing: 0) {
            // いちばん上：写真の選び直しと完了
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("写真", systemImage: "photo")
                }
                .buttonStyle(.bordered)
                Text("v\(appVersion)").font(.caption).foregroundStyle(.gray)
                Spacer()
                Button {
                    finish()
                } label: {
                    Label("完了", systemImage: "checkmark").bold()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if hasMap { mapSection }
                    textSection
                    dateSection(hasMap: hasMap)
                }
                .padding(14)
            }
        }
        .foregroundStyle(.white)
    }

    // 地図
    var mapSection: some View {
        PanelSection(title: "地図", systemImage: "map") {
            Toggle("地図を表示", isOn: $layout.showMap)

            if layout.showMap {
                // 範囲
                HStack {
                    Text("範囲").foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        layout.spanKm = max(10, layout.spanKm / 1.25)
                    } label: { Image(systemName: "plus.magnifyingglass") }
                    Text("\(Int(layout.spanKm)) km")
                        .font(.callout.monospacedDigit())
                        .frame(minWidth: 64)
                    Button {
                        layout.spanKm = min(2000, layout.spanKm * 1.25)
                    } label: { Image(systemName: "minus.magnifyingglass") }
                }
                .buttonStyle(.bordered)

                // 指で動かすもの
                Picker("指で動かすもの", selection: $moveMapContent) {
                    Text("枠").tag(false)
                    Text("中身").tag(true)
                }
                .pickerStyle(.segmented)

                if layout.mapOffset != .zero {
                    Button {
                        layout.mapOffset = .zero
                    } label: {
                        Label("撮影地を真ん中に戻す", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                }

                ColorPicker("線の色", selection: Binding(
                    get: { Color(uiColor: layout.mapColor) },
                    set: { layout.mapColor = UIColor($0) }), supportsOpacity: false)

                VStack(alignment: .leading, spacing: 6) {
                    Text("線の太さ").foregroundStyle(.secondary)
                    Picker("線の太さ", selection: $layout.lineWidthScale) {
                        ForEach(OverlayLayout.lineWidthChoices, id: \.scale) { choice in
                            Text(choice.name).tag(choice.scale)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("撮影地の県を塗る", isOn: $layout.mapFillPref)
                Toggle("撮影地の県を強調", isOn: $layout.mapEmphasize)
                Toggle("陸地をシルエットにする", isOn: $layout.mapSilhouette)
                Toggle("地図の背景を敷く", isOn: $layout.mapPlate)

                VStack(alignment: .leading, spacing: 6) {
                    Text("撮影地を指す手書き").foregroundStyle(.secondary)
                    Picker("撮影地を指す手書き", selection: $layout.hereMark) {
                        ForEach(HereMark.allCases, id: \.self) { m in
                            Text(m.name).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    // 文字（選んでいるかたまりの設定）
    var textSection: some View {
        PanelSection(title: "文字", systemImage: "textformat") {
            Picker("設定する文字", selection: $selectedText) {
                ForEach(TextKind.allCases, id: \.self) { k in
                    Text(k.name).tag(k)
                }
            }
            .pickerStyle(.segmented)

            Text("写真の上の文字をタップしても選べます")
                .font(.caption)
                .foregroundStyle(.secondary)

            ColorPicker("色", selection: Binding(
                get: { Color(uiColor: layout[keyPath: selectedText.keyPath].color) },
                set: { layout[keyPath: selectedText.keyPath].color = UIColor($0) }), supportsOpacity: false)

            if selectedText == .place {
                VStack(alignment: .leading, spacing: 6) {
                    Text("地名の前のマーク").foregroundStyle(.secondary)
                    Picker("地名の前のマーク", selection: $layout.placeMark) {
                        ForEach(PlaceMark.allCases, id: \.self) { m in
                            Text(m.name).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if selectedText != .here {
                Toggle("太字", isOn: Binding(
                    get: { layout[keyPath: selectedText.keyPath].bold },
                    set: { layout[keyPath: selectedText.keyPath].bold = $0 }))
                Toggle("背景を半透明で敷く", isOn: Binding(
                    get: { layout[keyPath: selectedText.keyPath].plate },
                    set: { layout[keyPath: selectedText.keyPath].plate = $0 }))
                VStack(alignment: .leading, spacing: 6) {
                    Text("フォント").foregroundStyle(.secondary)
                    Picker("フォント", selection: Binding(
                        get: { layout[keyPath: selectedText.keyPath].font },
                        set: { newFont in
                            layout[keyPath: selectedText.keyPath].font = newFont
                            // 日時を漢字のないフォントにしたら、日付の書き方を「/」に切り替える
                            if selectedText == .date && !newFont.supportsKanji && layout.dateNotation == .kanji {
                                layout.dateNotation = .slash
                            }
                            Task { await FontStore.shared.load(newFont) }
                        })) {
                        ForEach(TextFont.allCases, id: \.self) { f in
                            Text(f.name).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // 日時・緯度経度の出し方
    func dateSection(hasMap: Bool) -> some View {
        PanelSection(title: "日時・緯度経度", systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 6) {
                Text("日付の範囲").foregroundStyle(.secondary)
                Picker("日付の範囲", selection: $layout.dateStyle) {
                    ForEach(DateStyle.allCases, id: \.self) { style in
                        Text(style.name).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
            if layout.dateStyle != DateStyle.none {
                VStack(alignment: .leading, spacing: 6) {
                    Text("日付の書き方").foregroundStyle(.secondary)
                    Picker("日付の書き方", selection: $layout.dateNotation) {
                        ForEach(DateNotation.allCases.filter { $0 != .kanji || layout.date.font.supportsKanji }, id: \.self) { n in
                            Text(n.name).tag(n)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            Toggle("時刻を表示", isOn: $layout.showTime)
            if hasMap {
                Toggle("緯度・経度を表示", isOn: $layout.showCoordinate)
            }
        }
    }

    func loadPhoto(_ item: PhotosPickerItem) async {
        loading = true
        defer { loading = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let loaded = PhotoLoader.load(data) else {
            message = "写真を読み込めませんでした"
            return
        }
        info = loaded
        layout = OverlayLayout.initial(for: loaded.image.size, keeping: layout)
        moveMapContent = false
        place = ""
        if let c = loaded.coordinate {
            message = mapLines.isEmpty ? message : ""
            place = await PhotoLoader.placeName(for: c)
        } else {
            message = "この写真には位置情報が入っていませんでした。"
        }
    }

    func finish() {
        guard let info else { return }
        let image = Renderer.render(info: info, place: place, lines: mapLines, layout: layout)
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        result = RenderResult(image: image, jpeg: JPEGFile(data: data))
    }
}

// 設定一覧の見出し付きのまとまり
struct PanelSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - 編集画面（写真の上で地図と文字を動かす）

struct EditorView: View {
    let info: PhotoInfo
    let place: String
    let mapLines: [MapLine]
    let moveMapContent: Bool
    let fontsReady: Int          // フォントが読み込まれたら画面を描き直すための目印
    @Binding var selectedText: TextKind
    @Binding var layout: OverlayLayout

    // ジェスチャーの開始時の値
    @State private var mapDragStart: CGPoint?
    @State private var mapScaleStart: CGSize?
    @State private var offsetStart: CGPoint?
    @State private var spanStart: Double?
    @State private var handleStart: CGRect?
    @State private var textDragStart: CGPoint?
    @State private var textScaleStart: CGFloat?

    let handleSize: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let fit = fitSize(info.image.size, in: geo.size)
            let base = min(fit.width, fit.height)

            ZStack(alignment: .topLeading) {
                Image(uiImage: info.image)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)

                // 地図
                if layout.showMap, let c = info.coordinate, !mapLines.isEmpty {
                    let r = layout.mapRect(in: fit)
                    let viewCenter = layout.mapViewCenter(for: c)
                    let local = CGRect(origin: .zero, size: r.size)
                    MapPreview(lines: mapLines, center: viewCenter, photoPoint: c, layout: layout,
                               size: r.size, base: base,
                               dotPoint: MapData.project(c, in: local, center: viewCenter, spanKm: layout.spanKm))
                        .overlay(EditFrame(highlight: moveMapContent))
                        .contentShape(Rectangle())
                        .gesture(mapGesture(fit: fit, photoPoint: c))
                        .offset(x: r.minX, y: r.minY)

                    // 右下の角：ドラッグで縦横を自由に変える
                    if !moveMapContent {
                        ResizeHandle(size: handleSize)
                            .gesture(handleGesture(fit: fit))
                            .offset(x: r.maxX - handleSize / 2, y: r.maxY - handleSize / 2)
                    }
                }

                // 撮影地を指す手書き文字と矢印
                if layout.showMap, let c = info.coordinate, !mapLines.isEmpty,
                   let img = layout.hereMark.image, let hr = layout.hereRect(in: fit) {
                    let r = layout.mapRect(in: fit)
                    let viewCenter = layout.mapViewCenter(for: c)
                    let dot = MapData.project(c, in: r, center: viewCenter, spanKm: layout.spanKm)
                    let shadow = Color(uiColor: layout.here.color.contrastShadow).opacity(0.5)
                    if r.contains(dot),
                       let arrow = HereArrow.path(from: hr, to: dot, dotRadius: base * 0.013, width: hr.height * 0.09) {
                        Path(arrow)
                            .stroke(Color(uiColor: layout.here.color),
                                    style: StrokeStyle(lineWidth: hr.height * 0.09, lineCap: .round, lineJoin: .round))
                            .shadow(color: shadow, radius: hr.height * 0.03)
                            .frame(width: fit.width, height: fit.height)
                            .allowsHitTesting(false)
                    }
                    textBox(.here, fit: fit) {
                        Image(uiImage: img)
                            .renderingMode(.template)
                            .resizable()
                            .foregroundStyle(Color(uiColor: layout.here.color))
                            .frame(width: hr.width, height: hr.height)
                            .shadow(color: shadow, radius: hr.height * 0.03)
                    }
                }

                // 場所
                if !place.isEmpty {
                    textBox(.place, fit: fit) {
                        PlaceLabel(place: place, size: layout.place.fontSize(in: fit), item: layout.place, mark: layout.placeMark)
                    }
                }

                // 日時
                if let line = layout.dateLine(for: info) {
                    textBox(.date, fit: fit) {
                        InfoLabel(text: line, size: layout.date.fontSize(in: fit), item: layout.date)
                    }
                }

                // 緯度・経度
                if let line = layout.coordLine(for: info) {
                    textBox(.coord, fit: fit) {
                        InfoLabel(text: line, size: layout.coord.fontSize(in: fit), item: layout.coord)
                    }
                }
            }
            .frame(width: fit.width, height: fit.height, alignment: .topLeading)
            .clipped()
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    func fitSize(_ img: CGSize, in box: CGSize) -> CGSize {
        guard img.width > 0, img.height > 0 else { return .zero }
        let s = min(box.width / img.width, box.height / img.height)
        return CGSize(width: img.width * s, height: img.height * s)
    }

    // 文字のかたまり：タップで選択（色を変える対象）、1本指で移動、2本指でサイズ変更
    func textBox<Content: View>(_ kind: TextKind, fit: CGSize,
                                @ViewBuilder content: () -> Content) -> some View {
        let item = kind.keyPath
        let p = layout[keyPath: item].point(in: fit)
        let drag = DragGesture(coordinateSpace: .global)
            .onChanged { v in
                if selectedText != kind { selectedText = kind }
                let start = textDragStart ?? layout[keyPath: item].origin
                if textDragStart == nil { textDragStart = start }
                layout[keyPath: item].origin = CGPoint(
                    x: min(0.95, max(0, start.x + v.translation.width / fit.width)),
                    y: min(0.95, max(0, start.y + v.translation.height / fit.height)))
            }
            .onEnded { _ in textDragStart = nil }
        let pinch = MagnifyGesture()
            .onChanged { v in
                let start = textScaleStart ?? layout[keyPath: item].size
                if textScaleStart == nil { textScaleStart = start }
                layout[keyPath: item].size = min(0.15, max(0.012, start * v.magnification))
            }
            .onEnded { _ in textScaleStart = nil }

        return content()
            .padding(8)
            .overlay(EditFrame(highlight: selectedText == kind))
            .contentShape(Rectangle())
            .gesture(drag.simultaneously(with: pinch))
            .simultaneousGesture(TapGesture().onEnded { selectedText = kind })
            .offset(x: p.x - 8, y: p.y - 8)
    }

    // 地図：枠モードでは枠の移動・拡大縮小、中身モードでは地図の中身のずらし・ズーム
    func mapGesture(fit: CGSize, photoPoint: CLLocationCoordinate2D) -> some Gesture {
        let drag = DragGesture(coordinateSpace: .global)
            .onChanged { v in
                if moveMapContent {
                    let start = offsetStart ?? layout.mapOffset
                    if offsetStart == nil { offsetStart = start }
                    let rect = layout.mapRect(in: fit)
                    let d = MapData.degrees(for: v.translation, rectHeight: rect.height,
                                            center: layout.mapViewCenter(for: photoPoint), spanKm: layout.spanKm)
                    layout.mapOffset = CGPoint(x: start.x + d.x, y: start.y + d.y)
                } else {
                    let start = mapDragStart ?? layout.mapCenter
                    if mapDragStart == nil { mapDragStart = start }
                    layout.mapCenter = CGPoint(
                        x: min(1, max(0, start.x + v.translation.width / fit.width)),
                        y: min(1, max(0, start.y + v.translation.height / fit.height)))
                }
            }
            .onEnded { _ in
                mapDragStart = nil
                offsetStart = nil
            }
        let pinch = MagnifyGesture()
            .onChanged { v in
                if moveMapContent {
                    let start = spanStart ?? layout.spanKm
                    if spanStart == nil { spanStart = start }
                    layout.spanKm = min(2000, max(10, start / Double(v.magnification)))
                } else {
                    let start = mapScaleStart ?? CGSize(width: layout.mapWidth, height: layout.mapHeight)
                    if mapScaleStart == nil { mapScaleStart = start }
                    let k = v.magnification
                    layout.mapWidth = min(3, max(0.08, start.width * k))
                    layout.mapHeight = min(1.5, max(0.08, start.height * k))
                }
            }
            .onEnded { _ in
                mapScaleStart = nil
                spanStart = nil
            }
        return drag.simultaneously(with: pinch)
    }

    // 右下の角：左上を固定したまま、幅と高さを別々に変える
    func handleGesture(fit: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { v in
                let start = handleStart ?? layout.mapRect(in: fit)
                if handleStart == nil { handleStart = start }
                let base = min(fit.width, fit.height)
                let w = max(base * 0.08, start.width + v.translation.width)
                let h = max(base * 0.08, start.height + v.translation.height)
                layout.mapWidth = w / base
                layout.mapHeight = h / base
                layout.mapCenter = CGPoint(x: (start.minX + w / 2) / fit.width,
                                           y: (start.minY + h / 2) / fit.height)
            }
            .onEnded { _ in handleStart = nil }
    }
}

// 編集中だけ出る点線の枠
struct EditFrame: View {
    let highlight: Bool
    var body: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: highlight ? 2 : 1, dash: [6, 4]))
            .foregroundStyle(highlight ? Color.orange : Color.white.opacity(0.6))
    }
}

// 地図の枠の右下に出るつまみ
struct ResizeHandle: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 3)
        .contentShape(Circle())
    }
}

// 画面上の地図（完成画像と同じ見た目）
struct MapPreview: View {
    let lines: [MapLine]
    let center: CLLocationCoordinate2D
    let photoPoint: CLLocationCoordinate2D
    let layout: OverlayLayout
    let size: CGSize
    let base: CGFloat
    let dotPoint: CGPoint

    var body: some View {
        let prefGroup = MapData.prefectureGroup(at: photoPoint, lines: lines)
        let layers = MapData.layers(lines: lines, in: CGRect(origin: .zero, size: size), center: center,
                                    spanKm: layout.spanKm, prefGroup: prefGroup)
        let color = Color(uiColor: layout.mapColor)
        let width = max(0.75, base * 0.004 * layout.lineWidthScale)
        let fade = base * 0.04
        let fx = min(0.5, fade / max(size.width, 1))
        let fy = min(0.5, fade / max(size.height, 1))

        ZStack(alignment: .topLeading) {
            // 地図の後ろの半透明の背景
            if layout.mapPlate {
                RoundedRectangle(cornerRadius: base * 0.03)
                    .fill(Color(uiColor: MapLook.plateColor(for: layout.mapColor)))
                    .padding(base * 0.03)
                    .blur(radius: base * 0.02)
                    .frame(width: size.width, height: size.height)
            }

            ZStack {
                if layout.mapSilhouette {
                    Path(layers.land).fill(color.opacity(MapLook.silhouetteAlpha), style: FillStyle(eoFill: true))
                }
                if layout.mapFillPref && prefGroup != nil {
                    Path(layers.prefFill).fill(color.opacity(MapLook.prefFillAlpha), style: FillStyle(eoFill: true))
                }
                Group {
                    if layout.mapSilhouette {
                        if layout.mapEmphasize {
                            lineStroke(layers.prefLines, color: color, width: width * MapLook.prefWidth)
                        }
                    } else if layout.mapEmphasize {
                        lineStroke(layers.otherLines, color: color.opacity(MapLook.otherAlpha), width: width * MapLook.otherWidth)
                        lineStroke(layers.prefLines, color: color, width: width * MapLook.prefWidth)
                    } else {
                        lineStroke(layers.otherLines, color: color, width: width)
                        lineStroke(layers.prefLines, color: color, width: width)
                    }
                }
                .shadow(color: Color(uiColor: layout.mapColor.contrastShadow).opacity(0.45),
                        radius: base * 0.004 * layout.lineWidthScale)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .mask(fadeMask(fx, horizontal: true))
            .mask(fadeMask(fy, horizontal: false))

            if CGRect(origin: .zero, size: size).contains(dotPoint) {
                LocationDot(radius: base * 0.013)
                    .position(dotPoint)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    func lineStroke(_ path: CGPath, color: Color, width: CGFloat) -> some View {
        Path(path).stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    func fadeMask(_ f: CGFloat, horizontal: Bool) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: f),
            .init(color: .black, location: 1 - f),
            .init(color: .clear, location: 1)
        ], startPoint: horizontal ? .leading : .top, endPoint: horizontal ? .trailing : .bottom)
    }
}

// 撮影地の青い点
struct LocationDot: View {
    let radius: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.23, green: 0.6, blue: 1).opacity(0.35))
                .frame(width: radius * 5.2, height: radius * 5.2)
            Circle()
                .fill(Color.white)
                .frame(width: radius * 2.7, height: radius * 2.7)
                .shadow(color: .black.opacity(0.4), radius: radius * 0.3)
            Circle()
                .fill(Color(red: 0.18, green: 0.55, blue: 1))
                .frame(width: radius * 2, height: radius * 2)
        }
    }
}

// 文字の後ろの半透明の帯（文字の位置は動かさずに、外側へはみ出して敷く）
struct PlateBackground: ViewModifier {
    let item: TextItem
    let size: CGFloat

    func body(content: Content) -> some View {
        content.background(
            Group {
                if item.plate {
                    RoundedRectangle(cornerRadius: size * 0.35)
                        .fill(Color(uiColor: item.plateColor))
                        .padding(.horizontal, -size * TextItem.platePadX)
                        .padding(.vertical, -size * TextItem.platePadY)
                        .blur(radius: size * TextItem.plateFade * 0.35)
                }
            }
        )
    }
}

// 画面上の場所ラベル（完成画像と同じ並び）
struct PlaceLabel: View {
    let place: String
    let size: CGFloat
    let item: TextItem
    let mark: PlaceMark

    var body: some View {
        HStack(spacing: 0) {
            if mark != PlaceMark.none {
                PlaceMarkView(mark: mark, size: size * 1.35)
                    .frame(width: size * 1.8, alignment: .leading)
            }
            Text(place)
                .font(FontStore.shared.swiftUIFont(item.font, size: size, weight: item.bold ? .heavy : .semibold))
                .foregroundStyle(Color(uiColor: item.color))
                .shadow(color: Color(uiColor: item.color.contrastShadow).opacity(0.55), radius: size * 0.25)
        }
        .modifier(PlateBackground(item: item, size: size))
        .fixedSize()
    }
}

// 画面上の日時・緯度経度
struct InfoLabel: View {
    let text: String
    let size: CGFloat
    let item: TextItem

    var body: some View {
        Text(text)
            .font(FontStore.shared.swiftUIFont(item.font, size: size, weight: item.bold ? .bold : .medium))
            .foregroundStyle(Color(uiColor: item.color).opacity(0.85))
            .shadow(color: Color(uiColor: item.color.contrastShadow).opacity(0.55), radius: size * 0.25)
            .modifier(PlateBackground(item: item, size: size))
            .fixedSize()
    }
}

// MARK: - 完成画面

struct ResultView: View {
    let result: RenderResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(uiImage: result.image)
                    .resizable()
                    .scaledToFit()
                HStack(spacing: 16) {
                    Button {
                        dismiss()
                    } label: {
                        Label("編集に戻る", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: result.jpeg,
                              preview: SharePreview("TripMemory", image: Image(uiImage: result.image))) {
                        Label("保存・共有", systemImage: "square.and.arrow.up")
                            .bold()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}
