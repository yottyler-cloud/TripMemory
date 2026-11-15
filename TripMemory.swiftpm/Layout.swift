import SwiftUI
import CoreLocation

// 文字のかたまり1つ分（場所・日時・緯度経度）
struct TextItem {
    var origin: CGPoint      // 左上（写真の幅・高さに対する割合）
    var size: CGFloat        // 文字の大きさ（写真の短い辺に対する割合）
    var color: UIColor = .white
    var bold = false         // 太字
    var font: TextFont = .system
    var plate = false        // 文字の後ろに半透明の帯を敷く

    // 帯の色（明るい文字には暗い帯、暗い文字には明るい帯）
    var plateColor: UIColor {
        color.isDark ? UIColor.white.withAlphaComponent(0.55) : UIColor.black.withAlphaComponent(0.45)
    }

    // 帯の余白（文字の大きさに対する割合）
    static let platePadX: CGFloat = 0.45
    static let platePadY: CGFloat = 0.2
    // 帯のふちをぼかす幅（文字の大きさに対する割合）
    static let plateFade: CGFloat = 0.6

    func point(in s: CGSize) -> CGPoint {
        CGPoint(x: origin.x * s.width, y: origin.y * s.height)
    }

    func fontSize(in s: CGSize) -> CGFloat {
        size * min(s.width, s.height)
    }
}

// 地図と文字の配置（写真の大きさに対する割合で持つので、画面でも完成画像でも同じ配置になる）
struct OverlayLayout {
    // 地図の枠
    var mapCenter = CGPoint(x: 0.15, y: 0.7)    // 枠の中心（写真の幅・高さに対する割合）
    var mapWidth: CGFloat = 0.30                 // 枠の幅（写真の短い辺に対する割合）
    var mapHeight: CGFloat = 0.45                // 枠の高さ（写真の短い辺に対する割合）
    // 地図の中身
    var spanKm: Double = 250                     // 枠の縦方向に映す範囲（km）
    var mapOffset = CGPoint.zero                 // 撮影地からのずらし（度）x = 経度, y = 緯度
    var mapColor: UIColor = .white               // 線の色
    var lineWidthScale: CGFloat = 1.0            // 線の太さ（1.0 = 普通）
    var showMap = true                           // 地図を出すか
    var mapFillPref = false                      // 撮影地の県を塗る
    var mapEmphasize = false                     // 撮影地の県を強調（ほかの県は細く薄く）
    var mapSilhouette = false                    // 陸地をシルエットで塗る（県境は描かない）
    var mapPlate = false                         // 地図の後ろに半透明の背景を敷く

    // 文字
    var place = TextItem(origin: CGPoint(x: 0.05, y: 0.08), size: 0.04)
    var date = TextItem(origin: CGPoint(x: 0.05, y: 0.16), size: 0.04)
    var coord = TextItem(origin: CGPoint(x: 0.05, y: 0.22), size: 0.03)
    var here = TextItem(origin: CGPoint(x: 0.4, y: 0.4), size: 0.04,
                        color: UIColor(red: 0.84, green: 0.2, blue: 0.17, alpha: 1))
    var hereMark: HereMark = .none
    var placeMark: PlaceMark = .starPin
    var placeDetail: PlaceDetail = .city         // 地名をどこまで細かく出すか
    var placeLanguage: PlaceLanguage = .japanese // 地名の言葉
    var dateStyle: DateStyle = .full
    var dateNotation: DateNotation = .slash
    var showTime = true
    var showCoordinate = false

    // 線の太さの選択肢
    static let lineWidthChoices: [LineWidthChoice] = [
        LineWidthChoice(name: "極細", scale: 0.4),
        LineWidthChoice(name: "細い", scale: 0.65),
        LineWidthChoice(name: "普通", scale: 1.0),
        LineWidthChoice(name: "太い", scale: 1.5)
    ]

    // 写真に合わせた最初の配置（地図は左下、文字は左上）。範囲・色・表示の設定は前のものを引き継ぐ
    static func initial(for size: CGSize, keeping old: OverlayLayout) -> OverlayLayout {
        var l = OverlayLayout()
        l.spanKm = old.spanKm
        l.mapColor = old.mapColor
        l.lineWidthScale = old.lineWidthScale
        l.showMap = old.showMap
        l.mapFillPref = old.mapFillPref
        l.mapEmphasize = old.mapEmphasize
        l.mapSilhouette = old.mapSilhouette
        l.mapPlate = old.mapPlate
        for kind in TextKind.allCases {
            l[keyPath: kind.keyPath].color = old[keyPath: kind.keyPath].color
            l[keyPath: kind.keyPath].bold = old[keyPath: kind.keyPath].bold
            l[keyPath: kind.keyPath].plate = old[keyPath: kind.keyPath].plate
            l[keyPath: kind.keyPath].font = old[keyPath: kind.keyPath].font
        }
        l.dateStyle = old.dateStyle
        l.dateNotation = old.dateNotation
        l.showTime = old.showTime
        l.showCoordinate = old.showCoordinate
        l.hereMark = old.hereMark
        l.placeMark = old.placeMark
        l.placeDetail = old.placeDetail
        l.placeLanguage = old.placeLanguage
        guard size.width > 0, size.height > 0 else { return l }

        let base = min(size.width, size.height)
        let margin = base * 0.065
        let w = l.mapWidth * base, h = l.mapHeight * base
        l.mapCenter = CGPoint(x: (margin + w / 2) / size.width,
                              y: (size.height - margin - h / 2) / size.height)

        var y = margin
        l.place.origin = CGPoint(x: margin / size.width, y: y / size.height)
        y += l.place.size * base * 1.9
        l.date.origin = CGPoint(x: margin / size.width, y: y / size.height)
        y += l.date.size * base * 1.5
        l.coord.origin = CGPoint(x: margin / size.width, y: y / size.height)

        // 手書き文字は撮影地（地図の真ん中）の右上に置く
        let mapMid = CGPoint(x: l.mapCenter.x * size.width, y: l.mapCenter.y * size.height)
        l.here.origin = CGPoint(x: min(0.85, (mapMid.x + base * 0.1) / size.width),
                                y: max(0.02, (mapMid.y - base * 0.22) / size.height))
        return l
    }

    // 手書き文字の枠
    func hereRect(in size: CGSize) -> CGRect? {
        guard let img = hereMark.image, img.size.height > 0 else { return nil }
        let h = here.fontSize(in: size) * HereArrow.heightScale
        let w = h * img.size.width / img.size.height
        let p = here.point(in: size)
        return CGRect(x: p.x, y: p.y, width: w, height: h)
    }

    func mapRect(in size: CGSize) -> CGRect {
        let base = min(size.width, size.height)
        let w = mapWidth * base, h = mapHeight * base
        return CGRect(x: mapCenter.x * size.width - w / 2,
                      y: mapCenter.y * size.height - h / 2,
                      width: w, height: h)
    }

    // 地図の枠の真ん中にくる地点
    func mapViewCenter(for c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude + Double(mapOffset.y),
                               longitude: c.longitude + Double(mapOffset.x))
    }

    // 地名の文字（例：福島県 いわき市 小名浜 / Onahama, Iwaki, Fukushima）
    func placeText(_ n: PlaceNames) -> String {
        var parts: [String]
        switch placeLanguage {
        case .japanese:
            parts = [n.prefJa]
            if placeDetail != .prefecture { parts.append(n.cityJa) }
            if placeDetail == .town { parts.append(n.townJa) }
            return parts.filter { !$0.isEmpty }.joined(separator: " ")
        case .english:
            parts = [n.prefEn]
            if placeDetail != .prefecture { parts.insert(n.cityEn, at: 0) }
            if placeDetail == .town { parts.insert(n.townEn, at: 0) }
            return parts.filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    // 日時の文字（出さないときは nil）
    func dateLine(for info: PhotoInfo) -> String? {
        guard let d = info.date else { return nil }
        let y = d.year, m = d.month, dd = d.day
        let mi = Int(m) ?? 0, di = Int(dd) ?? 0
        var parts: [String] = []
        // 漢字のないフォントでは、漢字の書き方を「/」に置き換える
        let notation = (dateNotation == .kanji && !date.font.supportsKanji) ? DateNotation.slash : dateNotation
        switch (dateStyle, notation) {
        case (.none, _): break
        case (.full, .slash): parts.append("\(y)/\(m)/\(dd)")
        case (.full, .kanji): parts.append("\(y)年\(mi)月\(di)日")
        case (.full, .dmy): parts.append("\(dd)/\(m)/\(y)")
        case (.monthDay, .slash): parts.append("\(m)/\(dd)")
        case (.monthDay, .kanji): parts.append("\(mi)月\(di)日")
        case (.monthDay, .dmy): parts.append("\(dd)/\(m)")
        case (.yearMonth, .slash): parts.append("\(y)/\(m)")
        case (.yearMonth, .kanji): parts.append("\(y)年\(mi)月")
        case (.yearMonth, .dmy): parts.append("\(m)/\(y)")
        }
        if showTime { parts.append("\(d.hour):\(d.minute)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // 緯度・経度の文字（出さないときは nil）
    func coordLine(for info: PhotoInfo) -> String? {
        guard showCoordinate, let c = info.coordinate else { return nil }
        return String(format: "%.4f°%@  %.4f°%@",
                      abs(c.latitude), c.latitude >= 0 ? "N" : "S",
                      abs(c.longitude), c.longitude >= 0 ? "E" : "W")
    }
}

struct LineWidthChoice {
    let name: String
    let scale: CGFloat
}

enum DateStyle: String, CaseIterable {
    case full, monthDay, yearMonth, none

    var name: String {
        switch self {
        case .full: return "年月日"
        case .monthDay: return "月日"
        case .yearMonth: return "年月"
        case .none: return "日付なし"
        }
    }
}

// 日付の書き方
enum DateNotation: String, CaseIterable {
    case slash, kanji, dmy

    var name: String {
        switch self {
        case .slash: return "2026/06/01"
        case .kanji: return "2026年6月1日"
        case .dmy: return "01/06/2026（日/月/年）"
        }
    }
}

// 地名の細かさ
enum PlaceDetail: String, CaseIterable {
    case prefecture, city, town

    var name: String {
        switch self {
        case .prefecture: return "県"
        case .city: return "市まで"
        case .town: return "町まで"
        }
    }
}

// 地名の言葉
enum PlaceLanguage: String, CaseIterable {
    case japanese, english

    var name: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }
}

// 文字のかたまりの種類
enum TextKind: String, CaseIterable {
    case place, date, coord, here

    var keyPath: WritableKeyPath<OverlayLayout, TextItem> {
        switch self {
        case .place: return \OverlayLayout.place
        case .date: return \OverlayLayout.date
        case .coord: return \OverlayLayout.coord
        case .here: return \OverlayLayout.here
        }
    }

    var name: String {
        switch self {
        case .place: return "場所"
        case .date: return "日時"
        case .coord: return "緯度経度"
        case .here: return "手書き"
        }
    }
}

// 地図の見た目の決まりごと（編集画面と完成画像で同じ値を使う）
enum MapLook {
    static let silhouetteAlpha: CGFloat = 0.3
    static let prefFillAlpha: CGFloat = 0.35
    static let otherAlpha: CGFloat = 0.45
    static let otherWidth: CGFloat = 0.6
    static let prefWidth: CGFloat = 1.6

    // 背景の色（明るい線には暗い背景、暗い線には明るい背景）
    static func plateColor(for line: UIColor) -> UIColor {
        line.isDark ? UIColor.white.withAlphaComponent(0.5) : UIColor.black.withAlphaComponent(0.4)
    }
}

extension UIColor {
    // 暗い色かどうか（影の色を決めるのに使う）
    var isDark: Bool {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
    }

    // 線や文字を見やすくする影の色（暗い色には白い影、明るい色には黒い影）
    var contrastShadow: UIColor {
        isDark ? .white : .black
    }
}
