import Observation
import ServiceManagement

@MainActor
@Observable
final class AppChrome {
    var launchAtLogin: Bool
    var loginError: String?
    var hotkeyReady: Bool
    var isPinned: Bool
    var onPinnedChange: ((Bool) -> Void)?

    private let defaults = UserDefaults(suiteName: "local.luoyidong.shoutou") ?? .standard

    init() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        hotkeyReady = true
        isPinned = defaults.bool(forKey: "panelPinned")
        if status == .requiresApproval {
            loginError = "去系统设置的登录项里允许手头。"
        }
    }

    func setPinned(_ pinned: Bool) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        defaults.set(pinned, forKey: "panelPinned")
        onPinnedChange?(pinned)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = "没能改登录时打开。"
        }
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginError = "去系统设置的登录项里允许手头。"
        }
    }
}
