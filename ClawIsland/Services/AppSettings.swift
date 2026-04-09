import AppKit
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// 指定显示 island 的屏幕名称；nil 表示自动检测。
    @Published var preferredScreenName: String? {
        didSet {
            defaults.set(preferredScreenName, forKey: Keys.preferredScreenName)
        }
    }

    private enum Keys {
        static let preferredScreenName = "preferredScreenName"
    }

    private let defaults = UserDefaults.standard

    private init() {
        preferredScreenName = defaults.string(forKey: Keys.preferredScreenName)
    }

    // MARK: - Screen resolution

    /// 解析目标屏幕：优先用户指定 → 自动检测 → NSScreen.main
    func resolveScreen() -> NSScreen? {
        guard let name = preferredScreenName else {
            return Self.autoDetectScreen()
        }
        return NSScreen.screens.first { $0.localizedName == name }
            ?? Self.autoDetectScreen()
    }

    /// 自动检测最佳屏幕：有刘海的内置屏 → 内置屏 → 主屏
    static func autoDetectScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.screens.first { $0.localizedName.lowercased().contains("built-in") }
            ?? NSScreen.main
    }
}
