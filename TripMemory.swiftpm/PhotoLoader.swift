import SwiftUI
import ImageIO
import CoreLocation

// 読み込んだ写真と、その情報
struct PhotoInfo {
    var image: UIImage
    var coordinate: CLLocationCoordinate2D?
    var date: PhotoDate?
}

// 撮影日時（"2026:05:30 04:19:33" を分けて持つ）
struct PhotoDate {
    var year: String, month: String, day: String
    var hour: Int, minute: String

    init?(exif s: String) {
        let parts = s.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let d = parts[0].split(separator: ":")
        let t = parts[1].split(separator: ":")
        guard d.count >= 3, t.count >= 2, let h = Int(t[0]) else { return nil }
        year = String(d[0]); month = String(d[1]); day = String(d[2])
        hour = h; minute = String(t[1])
    }
}

enum PhotoLoader {
    static func load(_ data: Data) -> PhotoInfo? {
        guard let image = UIImage(data: data) else { return nil }
        var info = PhotoInfo(image: image, coordinate: nil, date: nil)

        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let d = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                info.date = PhotoDate(exif: d)
            }
            if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
               var lat = gps[kCGImagePropertyGPSLatitude] as? Double,
               var lon = gps[kCGImagePropertyGPSLongitude] as? Double {
                if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
                if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
                info.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
        return info
    }

    // 場所の名前（例：Fukushima, Japan）
    static func placeName(for c: CLLocationCoordinate2D) async -> String {
        let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let geocoder = CLGeocoder()
        if let placemarks = try? await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")),
           let pm = placemarks.first {
            return [pm.administrativeArea, pm.country].compactMap { $0 }.joined(separator: ", ")
        }
        return ""
    }
}
