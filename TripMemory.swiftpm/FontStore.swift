import SwiftUI
import CoreText

// 選べるフォント（どれも商用無料の SIL Open Font License）
enum TextFont: String, CaseIterable {
    case system, delaGothic, montserrat

    var name: String {
        switch self {
        case .system: return "標準"
        case .delaGothic: return "Dela Gothic One"
        case .montserrat: return "Montserrat（英数字）"
        }
    }

    // ネットから読み込むフォントの場所（標準は不要）
    var downloadURL: URL? {
        switch self {
        case .system: return nil
        case .delaGothic:
            return URL(string: "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/delagothicone/DelaGothicOne-Regular.ttf")
        case .montserrat:
            return URL(string: "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/montserrat/Montserrat%5Bwght%5D.ttf")
        }
    }

    // 漢字が入っているか（入っていないフォントでは日付を「/」の書き方だけにする）
    var supportsKanji: Bool { self != .montserrat }

    // 太さを自由に変えられるフォント（太字の切り替えが効く）
    var isVariable: Bool { self == .montserrat }

    var fileName: String { rawValue + ".ttf" }
}

// フォントの読み込みと登録（一度読み込んだら端末に保存して次回から使い回す）
final class FontStore: ObservableObject {
    static let shared = FontStore()

    @Published private(set) var registeredNames: [TextFont: String] = [:]
    @Published private(set) var loading: Set<TextFont> = []
    @Published var errorMessage = ""

    private var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    func isReady(_ font: TextFont) -> Bool {
        font == .system || registeredNames[font] != nil
    }

    func load(_ font: TextFont) async {
        guard let url = font.downloadURL, !isReady(font) else { return }
        await MainActor.run { _ = loading.insert(font) }
        let file = cacheDir.appendingPathComponent(font.fileName)
        do {
            if !FileManager.default.fileExists(atPath: file.path) {
                let (data, _) = try await URLSession.shared.data(from: url)
                try data.write(to: file)
            }
            guard let provider = CGDataProvider(url: file as CFURL),
                  let cgFont = CGFont(provider),
                  let psName = cgFont.postScriptName as String? else {
                try? FileManager.default.removeItem(at: file)
                throw URLError(.cannotDecodeContentData)
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterGraphicsFont(cgFont, &error)   // 登録済みでも続けて使える
            await MainActor.run {
                registeredNames[font] = psName
                loading.remove(font)
                errorMessage = ""
            }
        } catch {
            await MainActor.run {
                loading.remove(font)
                errorMessage = "フォント「\(font.name)」を読み込めませんでした。通信状態を確認してください。"
            }
        }
    }

    // 完成画像用
    func uiFont(_ font: TextFont, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        guard let name = registeredNames[font], let f = UIFont(name: name, size: size) else {
            return .systemFont(ofSize: size, weight: weight)
        }
        guard font.isVariable else { return f }
        // 太さの軸（wght）に数値を指定する
        let wghtAxis = 0x77676874
        let key = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = f.fontDescriptor.addingAttributes([key: [wghtAxis: weightValue(weight)]])
        return UIFont(descriptor: descriptor, size: size)
    }

    private func weightValue(_ w: UIFont.Weight) -> CGFloat {
        switch w {
        case .heavy, .black: return 800
        case .bold: return 700
        case .semibold: return 600
        case .medium: return 500
        default: return 400
        }
    }

    // 編集画面用（完成画像と同じフォントを使う）
    func swiftUIFont(_ font: TextFont, size: CGFloat, weight: UIFont.Weight) -> Font {
        if registeredNames[font] != nil {
            return Font(uiFont(font, size: size, weight: weight) as CTFont)
        }
        let swiftWeight: Font.Weight
        switch weight {
        case .heavy, .black: swiftWeight = .heavy
        case .bold: swiftWeight = .bold
        case .semibold: swiftWeight = .semibold
        case .medium: swiftWeight = .medium
        default: swiftWeight = .regular
        }
        return .system(size: size, weight: swiftWeight)
    }
}
