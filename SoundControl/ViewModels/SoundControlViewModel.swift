import AppKit
import Foundation

@MainActor
final class SoundControlViewModel: ObservableObject {
    @Published var volume: Double = 0
    @Published var volumeText = "音量：取得できません"
    @Published var isMuted = false
    @Published var outputDevices: [AudioDevice] = []
    @Published var errorMessage: String?
    @Published var isLoginItemEnabled = false
    @Published var canSetCurrentVolume = false
    @Published var canSetCurrentMute = false

    private let audioManager = AudioManager()
    private let loginItemManager = LoginItemManager()
    private let soundSettingsOpener = SoundSettingsOpener()

    func refresh() {
        do {
            let currentVolume = try audioManager.getOutputVolume()
            volume = Double(currentVolume)
            volumeText = "音量：\(Int((currentVolume * 100).rounded()))%"
        } catch {
            volumeText = "音量：取得できません"
            canSetCurrentVolume = false
            setError(error)
        }

        do {
            isMuted = try audioManager.getOutputMute()
        } catch {
            canSetCurrentMute = false
        }

        do {
            outputDevices = try audioManager.getOutputDevices()
            if let currentDevice = outputDevices.first(where: \.isDefaultOutput) {
                canSetCurrentVolume = currentDevice.canSetVolume
                canSetCurrentMute = currentDevice.canSetMute
            }
        } catch {
            outputDevices = []
            canSetCurrentVolume = false
            canSetCurrentMute = false
            setError(error)
        }

        isLoginItemEnabled = loginItemManager.isEnabled
    }

    func setVolume(_ newVolume: Double) {
        volume = min(max(newVolume, 0), 1)

        do {
            try audioManager.setOutputVolume(Float(volume))
            let currentVolume = try audioManager.getOutputVolume()
            volume = Double(currentVolume)
            volumeText = "音量：\(Int((currentVolume * 100).rounded()))%"
            errorMessage = nil
        } catch {
            setError(error)
            refresh()
        }
    }

    func adjustVolumeByScroll(deltaY: CGFloat) {
        guard canSetCurrentVolume, deltaY != 0 else {
            return
        }

        let step = 0.02
        setVolume(volume + (deltaY > 0 ? step : -step))
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted

        do {
            try audioManager.setOutputMute(muted)
            isMuted = try audioManager.getOutputMute()
            errorMessage = nil
        } catch {
            setError(error)
            refresh()
        }
    }

    func selectDevice(_ device: AudioDevice) {
        do {
            try audioManager.setDefaultOutputDevice(device.id)
            refresh()
            errorMessage = nil
        } catch {
            setError(error)
        }
    }

    func openSoundSettings() {
        do {
            try soundSettingsOpener.openSoundSettings()
            errorMessage = nil
        } catch {
            setError(error)
        }
    }

    func toggleLoginItem() {
        do {
            try loginItemManager.setEnabled(!isLoginItemEnabled)
            isLoginItemEnabled = loginItemManager.isEnabled
            errorMessage = nil
        } catch {
            setError(error)
            isLoginItemEnabled = loginItemManager.isEnabled
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func setError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
