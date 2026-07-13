import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let isDefaultOutput: Bool
    let canSetVolume: Bool
    let canSetMute: Bool
}
