import SwiftUI
import CoreLocation
import UniformTypeIdentifiers
import CoreImage

// 完成画像を作る
enum Renderer {
    static func render(info: PhotoInfo, place: String, lines: [MapLine], layout: OverlayLayout) -> UIImage {
        let image = info.image
        // 大きすぎる写真は縮小（メモリ対策）
        let maxPixels: CGFloat = 16_000_000
        let s = min(1, sqrt(maxPixels / (image.size.width * image.size.height)))
        let size = CGSize(width: (image.size.width * s).rounded(), height: (image.size.height * s).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
            let base = min(size.width, size.height)
            if layout.showMap, let c = info.coordinate, !lines.isEmpty {
                drawMap(ctx.cgContext, lines: lines, rect: layout.mapRect(in: size), base: base,
                        photoPoint: c, center: layout.mapViewCenter(for: c), layout: layout)

                // 撮影地を指す手書き文字と矢印
                let rect = layout.mapRect(in: size)
                let dot = MapData.project(c, in: rect, center: layout.mapViewCenter(for: c), spanKm: layout.spanKm)
                drawHere(ctx.cgContext, layout: layout, size: size, dot: rect.contains(dot) ? dot : nil,
                         dotRadius: base * 0.013)
            }
            drawPlace(place, at: layout.place.point(in: size), size: layout.place.fontSize(in: size),
                      item: layout.place, mark: layout.placeMark, cg: ctx.cgContext)
            if let line = layout.dateLine(for: info) {
                drawInfo(line, at: layout.date.point(in: size),
                         size: layout.date.fontSize(in: size), item: layout.date)
            }
            if let line = layout.coordLine(for: info) {
                drawInfo(line, at: layout.coord.point(in: size),
                         size: layout.coord.fontSize(in: size), item: layout.coord)
            }
        }
    }

    static func drawMap(_ cg: CGContext, lines: [MapLine], rect: CGRect, base: CGFloat,
                        photoPoint: CLLocationCoordinate2D, center c: CLLocationCoordinate2D,
                        layout: OverlayLayout) {
        let spanKm = layout.spanKm
        let color = layout.mapColor
        let prefGroup = MapData.prefectureGroup(at: photoPoint, lines: lines)
        let layers = MapData.layers(lines: lines, in: rect, center: c, spanKm: spanKm, prefGroup: prefGroup)
        let width = max(1, base * 0.004 * layout.lineWidthScale)

        cg.saveGState()
        cg.clip(to: rect)

        // 地図の後ろの半透明の背景（ふちはぼかす）
        if layout.mapPlate {
            drawSoftRect(rect.insetBy(dx: base * 0.03, dy: base * 0.03), blur: base * 0.02,
                         cornerRadius: base * 0.03, color: MapLook.plateColor(for: color))
        }

        cg.beginTransparencyLayer(auxiliaryInfo: nil)

        // 面
        if layout.mapSilhouette {
            cg.addPath(layers.land)
            cg.setFillColor(color.withAlphaComponent(MapLook.silhouetteAlpha).cgColor)
            cg.fillPath(using: .evenOdd)
        }
        if layout.mapFillPref, prefGroup != nil {
            cg.addPath(layers.prefFill)
            cg.setFillColor(color.withAlphaComponent(MapLook.prefFillAlpha).cgColor)
            cg.fillPath(using: .evenOdd)
        }

        // 線
        cg.setShadow(offset: .zero, blur: base * 0.006 * layout.lineWidthScale,
                     color: color.contrastShadow.withAlphaComponent(0.45).cgColor)
        cg.setLineJoin(.round)
        cg.setLineCap(.round)
        func stroke(_ path: CGPath, alpha: CGFloat, widthScale: CGFloat) {
            cg.addPath(path)
            cg.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            cg.setLineWidth(width * widthScale)
            cg.strokePath()
        }
        if layout.mapSilhouette {
            if layout.mapEmphasize { stroke(layers.prefLines, alpha: 1, widthScale: MapLook.prefWidth) }
        } else if layout.mapEmphasize {
            stroke(layers.otherLines, alpha: MapLook.otherAlpha, widthScale: MapLook.otherWidth)
            stroke(layers.prefLines, alpha: 1, widthScale: MapLook.prefWidth)
        } else {
            stroke(layers.otherLines, alpha: 1, widthScale: 1)
            stroke(layers.prefLines, alpha: 1, widthScale: 1)
        }

        // 端をふんわり消す
        cg.setShadow(offset: .zero, blur: 0, color: nil)
        cg.setBlendMode(.destinationOut)
        let fade = min(base * 0.04, rect.width / 2, rect.height / 2)
        let colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.minX + fade, y: 0), options: [])
            cg.drawLinearGradient(g, start: CGPoint(x: rect.maxX, y: 0), end: CGPoint(x: rect.maxX - fade, y: 0), options: [])
            cg.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.minY + fade), options: [])
            cg.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.maxY - fade), options: [])
        }
        cg.endTransparencyLayer()
        cg.restoreGState()

        // 撮影地の青い点（枠の外に出たときは描かない）
        let center = MapData.project(photoPoint, in: rect, center: c, spanKm: spanKm)
        guard rect.contains(center) else { return }
        let r = base * 0.013
        func circle(_ radius: CGFloat) -> CGRect {
            CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
        cg.saveGState()
        cg.setFillColor(UIColor(red: 0.23, green: 0.6, blue: 1, alpha: 0.35).cgColor)
        cg.fillEllipse(in: circle(r * 2.6))
        cg.setShadow(offset: .zero, blur: r * 0.6, color: UIColor.black.withAlphaComponent(0.4).cgColor)
        cg.setFillColor(UIColor.white.cgColor)
        cg.fillEllipse(in: circle(r * 1.35))
        cg.setShadow(offset: .zero, blur: 0, color: nil)
        cg.setFillColor(UIColor(red: 0.18, green: 0.55, blue: 1, alpha: 1).cgColor)
        cg.fillEllipse(in: circle(r))
        cg.restoreGState()
    }

    // 撮影地を指す手書き文字と、そこから撮影地へのカーブした矢印
    static func drawHere(_ cg: CGContext, layout: OverlayLayout, size: CGSize, dot: CGPoint?, dotRadius: CGFloat) {
        guard let img = layout.hereMark.image, let rect = layout.hereRect(in: size) else { return }
        let color = layout.here.color
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: rect.height * 0.06,
                     color: color.contrastShadow.withAlphaComponent(0.5).cgColor)
        let width = rect.height * 0.09
        if let dot, let arrow = HereArrow.path(from: rect, to: dot, dotRadius: dotRadius, width: width) {
            cg.addPath(arrow)
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(width)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.strokePath()
        }
        HandwritingAssets.tinted(img, color: color).draw(in: rect)
        cg.restoreGState()
    }

    static func textShadow(color: UIColor, size s: CGFloat) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = color.contrastShadow.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = s * 0.5
        shadow.shadowOffset = .zero
        return shadow
    }

    // 文字の後ろの半透明の帯（ふちはぼかして、外側ほど薄くする）
    static func drawPlate(around rect: CGRect, size s: CGFloat, item: TextItem) {
        guard item.plate else { return }
        let core = rect.insetBy(dx: -s * TextItem.platePadX, dy: -s * TextItem.platePadY)
        let blur = s * TextItem.plateFade * 0.35          // 編集画面のぼかしと同じ強さ
        let canvas = core.insetBy(dx: -blur * 3, dy: -blur * 3).integral

        // 帯だけを別の画像に描いて、ぼかしてから貼る
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let plateImage = UIGraphicsImageRenderer(size: canvas.size, format: format).image { _ in
            item.plateColor.setFill()
            UIBezierPath(roundedRect: core.offsetBy(dx: -canvas.minX, dy: -canvas.minY),
                         cornerRadius: s * 0.35).fill()
        }
        guard let input = CIImage(image: plateImage),
              let cg = ciContext.createCGImage(input.clampedToExtent().applyingGaussianBlur(sigma: blur)
                                                .cropped(to: input.extent), from: input.extent) else {
            item.plateColor.setFill()
            UIBezierPath(roundedRect: core, cornerRadius: s * 0.35).fill()
            return
        }
        UIImage(cgImage: cg).draw(in: canvas)
    }

    static let ciContext = CIContext()

    // ふちをぼかした角丸の四角（地図の背景用）
    static func drawSoftRect(_ core: CGRect, blur: CGFloat, cornerRadius: CGFloat, color: UIColor) {
        guard core.width > 0, core.height > 0 else { return }
        let canvas = core.insetBy(dx: -blur * 3, dy: -blur * 3).integral
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: canvas.size, format: format).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: core.offsetBy(dx: -canvas.minX, dy: -canvas.minY), cornerRadius: cornerRadius).fill()
        }
        guard let input = CIImage(image: img),
              let cg = ciContext.createCGImage(input.clampedToExtent().applyingGaussianBlur(sigma: blur)
                                                .cropped(to: input.extent), from: input.extent) else {
            color.setFill()
            UIBezierPath(roundedRect: core, cornerRadius: cornerRadius).fill()
            return
        }
        UIImage(cgImage: cg).draw(in: canvas)
    }

    // 場所（赤いピン付き）
    static func drawPlace(_ place: String, at p: CGPoint, size s: CGFloat, item: TextItem,
                          mark: PlaceMark, cg: CGContext) {
        guard !place.isEmpty else { return }
        let shadow = textShadow(color: item.color, size: s)
        let font = FontStore.shared.uiFont(item.font, size: s, weight: item.bold ? .heavy : .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: item.color, .shadow: shadow]
        let textSize = (place as NSString).size(withAttributes: attrs)
        let markSpace = mark == PlaceMark.none ? 0 : s * 1.8
        drawPlate(around: CGRect(x: p.x, y: p.y, width: markSpace + textSize.width, height: font.lineHeight),
                  size: s, item: item)

        // マーク（文字の高さの真ん中にそろえる）
        let markSize = s * 1.35
        mark.draw(in: cg, rect: CGRect(x: p.x, y: p.y + (font.lineHeight - markSize) / 2,
                                       width: markSize, height: markSize))
        (place as NSString).draw(at: CGPoint(x: p.x + markSpace, y: p.y), withAttributes: attrs)
    }

    // 日時・緯度経度
    static func drawInfo(_ text: String, at p: CGPoint, size s: CGFloat, item: TextItem) {
        let shadow = textShadow(color: item.color, size: s)
        let font = FontStore.shared.uiFont(item.font, size: s, weight: item.bold ? .bold : .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                    .foregroundColor: item.color.withAlphaComponent(0.85),
                                                    .shadow: shadow]
        let textSize = (text as NSString).size(withAttributes: attrs)
        drawPlate(around: CGRect(x: p.x, y: p.y, width: textSize.width, height: font.lineHeight),
                  size: s, item: item)
        (text as NSString).draw(at: p, withAttributes: attrs)
    }
}

// 保存・共有用のJPEG
struct JPEGFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { file in file.data }
    }
}

struct RenderResult: Identifiable {
    let id = UUID()
    let image: UIImage
    let jpeg: JPEGFile
}
