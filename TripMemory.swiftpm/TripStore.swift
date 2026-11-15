import SwiftUI
import CoreLocation

// ノートに貼った写真1枚
struct TripPhoto: Codable, Identifiable, Equatable {
    var id = UUID()
    var latitude: Double?
    var longitude: Double?
    var taken: Date?
    var prefecture = ""          // 例：福島県
    var x: Double = 0.5          // ページの中の位置（幅・高さに対する割合）
    var y: Double = 0.5
    var rotation: Double = 0     // 少し傾けて貼る
    var edited: Bool? = nil      // 地図などを重ねた画像に差し替えたか

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var fileName: String { id.uuidString + ".photo" }        // 元の写真（位置情報などもそのまま）
    var thumbName: String { id.uuidString + "_thumb.jpg" }   // ノートに表示する小さめの画像
    var editedName: String { id.uuidString + "_edited.jpg" } // 地図などを重ねた画像
}

// 旅ノート1冊
struct Trip: Codable, Identifiable, Equatable {
    var id = UUID()
    var created = Date()
    var coverIndex = 0
    var photos: [TripPhoto] = []

    static let coverColors: [Color] = [
        Color(red: 0.24, green: 0.42, blue: 0.56),
        Color(red: 0.71, green: 0.33, blue: 0.25),
        Color(red: 0.37, green: 0.48, blue: 0.29),
        Color(red: 0.42, green: 0.36, blue: 0.54),
        Color(red: 0.62, green: 0.47, blue: 0.20),
        Color(red: 0.25, green: 0.50, blue: 0.50)
    ]

    var coverColor: Color { Self.coverColors[coverIndex % Self.coverColors.count] }

    // 行った県（貼った順、重複なし）
    var prefectures: [String] {
        var seen: [String] = []
        for p in photos where !p.prefecture.isEmpty && !seen.contains(p.prefecture) {
            seen.append(p.prefecture)
        }
        return seen
    }

    var sortedDates: [Date] { photos.compactMap { $0.taken }.sorted() }

    // 題名は写真から自動で付ける（例：2026年5月 福島・宮城）
    var title: String {
        if photos.isEmpty { return "新しい旅" }
        let prefs = prefectures.map(Trip.shortPrefecture).joined(separator: "・")
        guard let first = sortedDates.first else { return prefs.isEmpty ? "旅の記録" : prefs }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return prefs.isEmpty ? f.string(from: first) : f.string(from: first) + " " + prefs
    }

    var dateRangeText: String {
        let dates = sortedDates
        guard let first = dates.first, let last = dates.last else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        let a = f.string(from: first), b = f.string(from: last)
        return a == b ? a : a + " – " + b
    }

    static func shortPrefecture(_ s: String) -> String {
        if s == "北海道" { return s }
        if s.hasSuffix("県") || s.hasSuffix("府") || s.hasSuffix("都") { return String(s.dropLast()) }
        return s
    }

    // ①②③…（21以上は (21) のように）
    static func circled(_ n: Int) -> String {
        if n >= 1 && n <= 20, let scalar = UnicodeScalar(0x2460 + n - 1) {
            return String(Character(scalar))
        }
        return "(\(n))"
    }
}

// 旅ノートの保存と読み込み（端末の中の「書類」フォルダに保存）
final class TripStore: ObservableObject {
    static let shared = TripStore()

    @Published private(set) var trips: [Trip] = []
    private let imageCache = NSCache<NSString, UIImage>()

    // 新しく貼る写真の置き場所（ページの中の割合）
    static let slots: [CGPoint] = [
        CGPoint(x: 0.27, y: 0.24), CGPoint(x: 0.72, y: 0.27),
        CGPoint(x: 0.30, y: 0.66), CGPoint(x: 0.73, y: 0.70),
        CGPoint(x: 0.50, y: 0.46)
    ]

    private var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Trips", isDirectory: true)
    }

    init() {
        load()
    }

    func folder(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func load() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var list: [Trip] = []
        for dir in dirs {
            if let data = try? Data(contentsOf: dir.appendingPathComponent("trip.json")),
               let trip = try? JSONDecoder().decode(Trip.self, from: data) {
                list.append(trip)
            }
        }
        trips = list.sorted { $0.created > $1.created }
    }

    func trip(_ id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    func save(_ trip: Trip) {
        let dir = folder(trip.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(trip) {
            try? data.write(to: dir.appendingPathComponent("trip.json"))
        }
        if let i = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[i] = trip
        } else {
            trips.insert(trip, at: 0)
        }
    }

    func update(_ id: UUID, _ change: (inout Trip) -> Void) {
        guard var t = trip(id) else { return }
        change(&t)
        save(t)
    }

    func newTrip() -> Trip {
        var t = Trip()
        t.coverIndex = trips.count % Trip.coverColors.count
        save(t)
        return t
    }

    func delete(_ trip: Trip) {
        try? FileManager.default.removeItem(at: folder(trip.id))
        trips.removeAll { $0.id == trip.id }
    }

    // MARK: - 写真

    func originalData(_ tripID: UUID, _ photo: TripPhoto) -> Data? {
        try? Data(contentsOf: folder(tripID).appendingPathComponent(photo.fileName))
    }

    func thumbnail(_ tripID: UUID, _ photo: TripPhoto) -> UIImage? {
        let key = photo.id.uuidString as NSString
        if let img = imageCache.object(forKey: key) { return img }
        let url = folder(tripID).appendingPathComponent(photo.thumbName)
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache.setObject(img, forKey: key)
        return img
    }

    func removePhoto(_ photo: TripPhoto, from tripID: UUID) {
        let dir = folder(tripID)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(photo.fileName))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(photo.thumbName))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(photo.editedName))
        imageCache.removeObject(forKey: photo.id.uuidString as NSString)
        update(tripID) { t in t.photos.removeAll { $0.id == photo.id } }
    }

    // 編集画面で作った画像を、ノートの写真として差し替える
    func saveEdited(_ image: UIImage, photoID: UUID, tripID: UUID) {
        guard let photo = trip(tripID)?.photos.first(where: { $0.id == photoID }) else { return }
        let dir = folder(tripID)
        if let jpg = image.jpegData(compressionQuality: 0.9) {
            try? jpg.write(to: dir.appendingPathComponent(photo.editedName))
        }
        writeThumbnail(from: image, for: photo, in: dir)
        update(tripID) { t in
            if let i = t.photos.firstIndex(where: { $0.id == photoID }) { t.photos[i].edited = true }
        }
    }

    // 加工前の写真に戻す
    func revertEdited(photoID: UUID, tripID: UUID) {
        guard let photo = trip(tripID)?.photos.first(where: { $0.id == photoID }) else { return }
        let dir = folder(tripID)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(photo.editedName))
        if let data = originalData(tripID, photo), let original = UIImage(data: data) {
            writeThumbnail(from: original, for: photo, in: dir)
        }
        update(tripID) { t in
            if let i = t.photos.firstIndex(where: { $0.id == photoID }) { t.photos[i].edited = nil }
        }
    }

    private func writeThumbnail(from image: UIImage, for photo: TripPhoto, in dir: URL) {
        if let thumb = Self.makeThumbnail(image, maxSide: 1200), let jpg = thumb.jpegData(compressionQuality: 0.85) {
            try? jpg.write(to: dir.appendingPathComponent(photo.thumbName))
        }
        imageCache.removeObject(forKey: photo.id.uuidString as NSString)
    }

    @MainActor
    func addPhoto(data: Data, to tripID: UUID) async {
        guard let info = PhotoLoader.load(data) else { return }
        var photo = TripPhoto()
        photo.latitude = info.coordinate?.latitude
        photo.longitude = info.coordinate?.longitude
        photo.taken = info.date?.asDate
        photo.rotation = Double.random(in: -4...4)
        if let c = info.coordinate {
            photo.prefecture = await PhotoLoader.prefectureJa(for: c)
        }

        let dir = folder(tripID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(photo.fileName))
        if let thumb = Self.makeThumbnail(info.image, maxSide: 1200),
           let jpg = thumb.jpegData(compressionQuality: 0.85) {
            try? jpg.write(to: dir.appendingPathComponent(photo.thumbName))
        }

        update(tripID) { t in
            let slot = Self.slots[t.photos.count % Self.slots.count]
            let round = Double(t.photos.count / Self.slots.count)
            photo.x = min(0.9, max(0.1, slot.x + round * 0.04))
            photo.y = min(0.9, max(0.1, slot.y + round * 0.04))
            t.photos.append(photo)
        }
    }

    static func makeThumbnail(_ image: UIImage, maxSide: CGFloat) -> UIImage? {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let s = min(1, maxSide / max(w, h))
        let size = CGSize(width: (w * s).rounded(), height: (h * s).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension PhotoDate {
    var asDate: Date? {
        var c = DateComponents()
        c.year = Int(year)
        c.month = Int(month)
        c.day = Int(day)
        c.hour = hour
        c.minute = Int(minute)
        return Calendar(identifier: .gregorian).date(from: c)
    }
}

extension PhotoLoader {
    // 日本語の県名（例：福島県）
    static func prefectureJa(for c: CLLocationCoordinate2D) async -> String {
        let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let geocoder = CLGeocoder()
        if let placemarks = try? await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ja_JP")),
           let pm = placemarks.first {
            return pm.administrativeArea ?? ""
        }
        return ""
    }
}
