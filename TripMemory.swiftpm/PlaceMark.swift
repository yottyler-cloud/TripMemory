import SwiftUI

// 地名の前に付けるマーク
enum PlaceMark: String, CaseIterable {
    case starPin, camera, flag, none

    var name: String {
        switch self {
        case .starPin: return "星つきピン"
        case .camera: return "カメラ"
        case .flag: return "旗"
        case .none: return "なし"
        }
    }

    static let color = UIColor(red: 0.886, green: 0.294, blue: 0.29, alpha: 1)

    // マークの部品（24×24 の中の形）
    enum Paint { case main, white, faded }
    struct Layer {
        let path: CGPath
        let paint: Paint
    }

    var layers: [Layer] {
        switch self {
        case .none:
            return []

        case .starPin:
            let pin = CGMutablePath()
            pin.move(to: CGPoint(x: 12, y: 2))
            pin.addCurve(to: CGPoint(x: 4, y: 9.9), control1: CGPoint(x: 7.6, y: 2), control2: CGPoint(x: 4, y: 5.5))
            pin.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 4, y: 15.5), control2: CGPoint(x: 12, y: 22))
            pin.addCurve(to: CGPoint(x: 20, y: 9.9), control1: CGPoint(x: 12, y: 22), control2: CGPoint(x: 20, y: 15.5))
            pin.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 20, y: 5.5), control2: CGPoint(x: 16.4, y: 2))
            pin.closeSubpath()
            let star = CGMutablePath()
            star.addLines(between: [
                CGPoint(x: 12, y: 5.6), CGPoint(x: 13.3, y: 8.3), CGPoint(x: 16.3, y: 8.7),
                CGPoint(x: 14.1, y: 10.8), CGPoint(x: 14.6, y: 13.8), CGPoint(x: 12, y: 12.4),
                CGPoint(x: 9.4, y: 13.8), CGPoint(x: 9.9, y: 10.8), CGPoint(x: 7.7, y: 8.7),
                CGPoint(x: 10.7, y: 8.3)
            ])
            star.closeSubpath()
            return [Layer(path: pin, paint: .main), Layer(path: star, paint: .white)]

        case .camera:
            let body = CGMutablePath()
            body.addRoundedRect(in: CGRect(x: 3, y: 7, width: 18, height: 13), cornerWidth: 2.5, cornerHeight: 2.5)
            body.move(to: CGPoint(x: 8.5, y: 7.5))
            body.addLine(to: CGPoint(x: 10, y: 4.5))
            body.addLine(to: CGPoint(x: 14, y: 4.5))
            body.addLine(to: CGPoint(x: 15.5, y: 7.5))
            body.closeSubpath()
            let lens = CGPath(ellipseIn: CGRect(x: 12 - 3.8, y: 13.5 - 3.8, width: 7.6, height: 7.6), transform: nil)
            let inner = CGPath(ellipseIn: CGRect(x: 12 - 2.2, y: 13.5 - 2.2, width: 4.4, height: 4.4), transform: nil)
            return [Layer(path: body, paint: .main), Layer(path: lens, paint: .white), Layer(path: inner, paint: .main)]

        case .flag:
            let pole = CGPath(roundedRect: CGRect(x: 5, y: 3, width: 2, height: 18), cornerWidth: 1, cornerHeight: 1, transform: nil)
            let cloth = CGMutablePath()
            cloth.addLines(between: [CGPoint(x: 6.5, y: 4), CGPoint(x: 19, y: 7.5), CGPoint(x: 6.5, y: 11)])
            cloth.closeSubpath()
            let base = CGPath(ellipseIn: CGRect(x: 3, y: 20, width: 6, height: 2), transform: nil)
            return [Layer(path: base, paint: .faded), Layer(path: pole, paint: .main), Layer(path: cloth, paint: .main)]
        }
    }

    // 完成画像用：rect の中にマークを描く
    func draw(in cg: CGContext, rect: CGRect) {
        guard self != PlaceMark.none else { return }
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.minY)
        cg.scaleBy(x: rect.width / 24, y: rect.height / 24)
        for layer in layers {
            cg.addPath(layer.path)
            cg.setFillColor(Self.uiColor(layer.paint).cgColor)
            cg.fillPath()
        }
        cg.restoreGState()
    }

    static func uiColor(_ paint: Paint) -> UIColor {
        switch paint {
        case .main: return color
        case .white: return .white
        case .faded: return color.withAlphaComponent(0.6)
        }
    }
}

// 編集画面用のマーク
struct PlaceMarkView: View {
    let mark: PlaceMark
    let size: CGFloat

    var body: some View {
        let k = size / 24
        let layers = mark.layers
        ZStack(alignment: .topLeading) {
            ForEach(layers.indices, id: \.self) { i in
                Path(layers[i].path)
                    .applying(CGAffineTransform(scaleX: k, y: k))
                    .fill(Color(uiColor: PlaceMark.uiColor(layers[i].paint)))
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}
