import AppKit
import Foundation

enum SoundSettingsOpenerError: LocalizedError {
    case failed

    var errorDescription: String? {
        switch self {
        case .failed:
            return "サウンド設定を開けませんでした"
        }
    }
}

final class SoundSettingsOpener {
    func openSoundSettings() throws {
        let soundSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")
        if let soundSettingsURL, NSWorkspace.shared.open(soundSettingsURL) {
            return
        }

        let systemSettingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        if NSWorkspace.shared.open(systemSettingsURL) {
            return
        }

        throw SoundSettingsOpenerError.failed
    }
}
