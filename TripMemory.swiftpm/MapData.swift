import SwiftUI
import CoreLocation

// 地図の線1本分（県の輪郭・湖の輪郭）
struct MapLine {
    var points: [CGPoint]   // x = 経度, y = 緯度
    var group: Int          // どの県か（0〜）。湖は -1
    var minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat

    var isLake: Bool { group < 0 }

    init(points: [CGPoint], group: Int) {
        self.points = points
        self.group = group
        minX = points.map { $0.x }.min() ?? 0
        maxX = points.map { $0.x }.max() ?? 0
        minY = points.map { $0.y }.min() ?? 0
        maxY = points.map { $0.y }.max() ?? 0
    }
}

enum MapData {
    // 都道府県の境界データ（海岸線・県境）：地球地図日本（国土地理院）をもとにしたデータ
    static let url = URL(string: "https://cdn.jsdelivr.net/gh/dataofjapan/land@master/japan.geojson")!
    // 湖のデータ：Natural Earth（世界の湖。日本のまわりだけ使う）
    static let lakesURL = URL(string: "https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector@master/geojson/ne_10m_lakes.geojson")!

    static func load() async throws -> [MapLine] {
        async let lakes = loadLakes()
        let data = try await cachedData(url, name: "japan.geojson")
        return parse(data, isLake: false) + (await lakes)
    }

    // 湖は読み込めなくても地図は出す
    static func loadLakes() async -> [MapLine] {
        guard let data = try? await cachedData(lakesURL, name: "lakes.geojson") else { return [] }
        // 日本のまわり（経度122〜154度、緯度20〜46度）にある湖だけ残す
        return parse(data, isLake: true).filter { $0.maxX >= 122 && $0.minX <= 154 && $0.maxY >= 20 && $0.minY <= 46 }
    }

    // 一度読み込んだデータは端末に保存して、次からはそれを使う
    static func cachedData(_ url: URL, name: String) async throws -> Data {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let file = dir.appendingPathComponent(name)
        if let data = try? Data(contentsOf: file), !data.isEmpty { return data }
        let (data, _) = try await URLSession.shared.data(from: url)
        try? data.write(to: file)
        return data
    }

    static func parse(_ data: Data, isLake: Bool) -> [MapLine] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return [] }
        var lines: [MapLine] = []
        for (index, feature) in features.enumerated() {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String,
                  let coords = geometry["coordinates"] as? [Any] else { continue }
            let polygons: [Any] = (type == "Polygon") ? [coords] : coords
            for polygon in polygons {
                guard let rings = polygon as? [[[Double]]] else { continue }
                for ring in rings where ring.count > 1 {
                    lines.append(MapLine(points: ring.map { CGPoint(x: $0[0], y: $0[1]) },
                                         group: isLake ? -1 : index))
                }
            }
        }
        return lines
    }

    /// 撮影地がどの県に入っているか（見つからなければ nil）
    static func prefectureGroup(at c: CLLocationCoordinate2D, lines: [MapLine]) -> Int? {
        let x = CGFloat(c.longitude), y = CGFloat(c.latitude)
        var best: (group: Int, dist: CGFloat)?
        for line in lines where !line.isLake {
            if x >= line.minX && x <= line.maxX && y >= line.minY && y <= line.maxY && contains(line.points, x, y) {
                return line.group
            }
        }
        // 海岸ぎりぎりで外れたときは、いちばん近い県にする
        for line in lines where !line.isLake {
            if x < line.minX - 0.2 || x > line.maxX + 0.2 || y < line.minY - 0.2 || y > line.maxY + 0.2 { continue }
            for p in line.points {
                let d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)
                if best == nil || d < best!.dist { best = (line.group, d) }
            }
        }
        if let best, best.dist < 0.01 { return best.group }
        return nil
    }

    private static func contains(_ ring: [CGPoint], _ x: CGFloat, _ y: CGFloat) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.y > y) != (b.y > y) && x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// 地図の見た目ごとに分けた線と面
    struct Layers {
        var land = CGMutablePath()          // 陸地（湖は穴）
        var prefFill = CGMutablePath()      // 撮影地の県（湖は穴）
        var otherLines = CGMutablePath()    // ほかの県と湖の輪郭
        var prefLines = CGMutablePath()     // 撮影地の県の輪郭
    }

    static func layers(lines: [MapLine], in rect: CGRect, center c: CLLocationCoordinate2D,
                       spanKm: Double, prefGroup: Int?) -> Layers {
        let result = Layers()
        guard rect.height > 0, rect.width > 0 else { return result }
        let lat0 = CGFloat(c.latitude), lon0 = CGFloat(c.longitude)
        let degLat = CGFloat(spanKm / 111)
        let sc = rect.height / degLat
        let cosLat = CGFloat(cos(c.latitude * .pi / 180))
        let halfLon = (rect.width / 2) / (sc * cosLat)
        let halfLat = degLat / 2

        // 撮影地の県の範囲（湖がその県の中にあるかの目安）
        var prefBox: CGRect?
        if let g = prefGroup {
            for line in lines where line.group == g {
                let box = CGRect(x: line.minX, y: line.minY, width: line.maxX - line.minX, height: line.maxY - line.minY)
                prefBox = prefBox?.union(box) ?? box
            }
        }

        for line in lines {
            if line.maxX < lon0 - halfLon || line.minX > lon0 + halfLon ||
               line.maxY < lat0 - halfLat || line.minY > lat0 + halfLat { continue }
            let ring = CGMutablePath()
            for (i, p) in line.points.enumerated() {
                let pt = CGPoint(x: rect.midX + (p.x - lon0) * sc * cosLat,
                                 y: rect.midY - (p.y - lat0) * sc)
                if i == 0 { ring.move(to: pt) } else { ring.addLine(to: pt) }
            }
            ring.closeSubpath()

            result.land.addPath(ring)
            let isPref = prefGroup != nil && line.group == prefGroup
            let lakeInPref = line.isLake && prefBox?.contains(CGPoint(x: (line.minX + line.maxX) / 2,
                                                                      y: (line.minY + line.maxY) / 2)) == true
            if isPref || lakeInPref { result.prefFill.addPath(ring) }
            if isPref { result.prefLines.addPath(ring) } else { result.otherLines.addPath(ring) }
        }
        return result
    }

    /// 地図上の1点が rect の中のどこにくるか
    static func project(_ point: CLLocationCoordinate2D, in rect: CGRect,
                        center c: CLLocationCoordinate2D, spanKm: Double) -> CGPoint {
        let sc = rect.height / CGFloat(spanKm / 111)
        let cosLat = CGFloat(cos(c.latitude * .pi / 180))
        return CGPoint(x: rect.midX + CGFloat(point.longitude - c.longitude) * sc * cosLat,
                       y: rect.midY - CGFloat(point.latitude - c.latitude) * sc)
    }

    /// 画面上でずらした量（ポイント）を、地図のずらし（度）に直す
    static func degrees(for translation: CGSize, rectHeight: CGFloat,
                        center c: CLLocationCoordinate2D, spanKm: Double) -> CGPoint {
        let sc = rectHeight / CGFloat(spanKm / 111)
        let cosLat = CGFloat(cos(c.latitude * .pi / 180))
        return CGPoint(x: -translation.width / (sc * cosLat), y: translation.height / sc)
    }

    /// rect の中に、center を真ん中にした地図の線を作る
    static func path(lines: [MapLine], in rect: CGRect, center c: CLLocationCoordinate2D, spanKm: Double) -> CGPath {
        let path = CGMutablePath()
        guard rect.height > 0, rect.width > 0 else { return path }
        let lat0 = CGFloat(c.latitude), lon0 = CGFloat(c.longitude)
        let degLat = CGFloat(spanKm / 111)                  // 縦方向の範囲（度）
        let sc = rect.height / degLat                        // 1度あたりの長さ
        let cosLat = CGFloat(cos(c.latitude * .pi / 180))
        let halfLon = (rect.width / 2) / (sc * cosLat)
        let halfLat = degLat / 2

        for line in lines {
            if line.maxX < lon0 - halfLon || line.minX > lon0 + halfLon ||
               line.maxY < lat0 - halfLat || line.minY > lat0 + halfLat { continue }
            for (i, p) in line.points.enumerated() {
                let pt = CGPoint(x: rect.midX + (p.x - lon0) * sc * cosLat,
                                 y: rect.midY - (p.y - lat0) * sc)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
        }
        return path
    }
}

// 地図データをアプリ全体で1回だけ読み込んで使い回す
final class MapStore: ObservableObject {
    static let shared = MapStore()

    @Published private(set) var lines: [MapLine] = []
    @Published private(set) var failed = false
    private var loadingTask: Task<Void, Never>?

    @MainActor
    func loadIfNeeded() async {
        if !lines.isEmpty { return }
        if let task = loadingTask {
            await task.value
            return
        }
        let task = Task { @MainActor in
            do {
                let loaded = try await MapData.load()
                self.lines = loaded
                self.failed = false
            } catch {
                self.failed = true
            }
        }
        loadingTask = task
        await task.value
        loadingTask = nil
    }
}
