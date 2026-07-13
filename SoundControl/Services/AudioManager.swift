import CoreAudio
import Foundation

enum AudioManagerError: LocalizedError {
    case propertyUnavailable(String)
    case operationFailed(String, OSStatus)
    case unsupportedVolume
    case unsupportedMute
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .propertyUnavailable(let message):
            return message
        case .operationFailed(let message, let status):
            return "\(message) (OSStatus: \(status))"
        case .unsupportedVolume:
            return "この出力デバイスでは音量変更できません"
        case .unsupportedMute:
            return "この出力デバイスではミュート変更できません"
        case .deviceNotFound:
            return "出力デバイスが見つかりませんでした"
        }
    }
}

final class AudioManager {
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

    func getOutputVolume() throws -> Float {
        let deviceID = try getDefaultOutputDevice()
        if hasProperty(selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, objectID: deviceID) {
            return try readFloat32(selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, objectID: deviceID)
        }

        let channelVolumes = try outputChannelElements(for: deviceID).compactMap { element -> Float? in
            guard hasProperty(selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: element, objectID: deviceID) else {
                return nil
            }

            return try? readFloat32(selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: element, objectID: deviceID)
        }

        guard !channelVolumes.isEmpty else {
            throw AudioManagerError.unsupportedVolume
        }

        return channelVolumes.reduce(0, +) / Float(channelVolumes.count)
    }

    func setOutputVolume(_ volume: Float) throws {
        let deviceID = try getDefaultOutputDevice()
        let clampedVolume = min(max(volume, 0), 1)

        if isPropertySettable(selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, objectID: deviceID) {
            try writeFloat32(clampedVolume, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, objectID: deviceID)
            return
        }

        let writableChannels = try outputChannelElements(for: deviceID).filter {
            isPropertySettable(selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: $0, objectID: deviceID)
        }

        guard !writableChannels.isEmpty else {
            throw AudioManagerError.unsupportedVolume
        }

        for element in writableChannels {
            try writeFloat32(clampedVolume, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: element, objectID: deviceID)
        }
    }

    func getOutputMute() throws -> Bool {
        let deviceID = try getDefaultOutputDevice()
        if hasProperty(selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, objectID: deviceID) {
            return try readUInt32(selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, objectID: deviceID) != 0
        }

        for element in try outputChannelElements(for: deviceID) {
            guard hasProperty(selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: element, objectID: deviceID) else {
                continue
            }

            return try readUInt32(selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: element, objectID: deviceID) != 0
        }

        throw AudioManagerError.unsupportedMute
    }

    func setOutputMute(_ muted: Bool) throws {
        let deviceID = try getDefaultOutputDevice()
        let muteValue: UInt32 = muted ? 1 : 0

        if isPropertySettable(selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, objectID: deviceID) {
            try writeUInt32(muteValue, selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, objectID: deviceID)
            return
        }

        let writableChannels = try outputChannelElements(for: deviceID).filter {
            isPropertySettable(selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: $0, objectID: deviceID)
        }

        guard !writableChannels.isEmpty else {
            throw AudioManagerError.unsupportedMute
        }

        for element in writableChannels {
            try writeUInt32(muteValue, selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: element, objectID: deviceID)
        }
    }

    func getOutputDevices() throws -> [AudioDevice] {
        let defaultDeviceID = try? getDefaultOutputDevice()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize)
        guard status == noErr else {
            throw AudioManagerError.operationFailed("出力デバイス一覧を取得できませんでした", status)
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else {
            throw AudioManagerError.operationFailed("出力デバイス一覧を取得できませんでした", status)
        }

        return try deviceIDs.compactMap { deviceID in
            guard hasOutputStreams(deviceID: deviceID) else {
                return nil
            }

            return AudioDevice(
                id: deviceID,
                name: (try? getDeviceName(deviceID)) ?? "Unknown Device",
                isDefaultOutput: deviceID == defaultDeviceID,
                canSetVolume: canSetOutputVolume(deviceID: deviceID),
                canSetMute: canSetOutputMute(deviceID: deviceID)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDefaultOutput != rhs.isDefaultOutput {
                return lhs.isDefaultOutput
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func getDefaultOutputDevice() throws -> AudioDeviceID {
        try readAudioDeviceID(
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain,
            objectID: systemObjectID
        )
    }

    func setDefaultOutputDevice(_ deviceID: AudioDeviceID) throws {
        try writeAudioDeviceID(
            deviceID,
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain,
            objectID: systemObjectID
        )
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name)
        guard status == noErr else {
            throw AudioManagerError.operationFailed("デバイス名を取得できませんでした", status)
        }

        return name as String
    }

    private func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private func canSetOutputVolume(deviceID: AudioDeviceID) -> Bool {
        isPropertySettable(selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, objectID: deviceID)
            || ((try? outputChannelElements(for: deviceID)) ?? []).contains {
                isPropertySettable(selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: $0, objectID: deviceID)
            }
    }

    private func canSetOutputMute(deviceID: AudioDeviceID) -> Bool {
        isPropertySettable(selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: kAudioObjectPropertyElementMain, objectID: deviceID)
            || ((try? outputChannelElements(for: deviceID)) ?? []).contains {
                isPropertySettable(selector: kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: $0, objectID: deviceID)
            }
    }

    private func outputChannelElements(for deviceID: AudioDeviceID) throws -> [AudioObjectPropertyElement] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr else {
            throw AudioManagerError.operationFailed("出力チャンネルを取得できませんでした", status)
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer {
            bufferListPointer.deallocate()
        }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else {
            throw AudioManagerError.operationFailed("出力チャンネルを取得できませんでした", status)
        }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let channelCount = buffers.reduce(0) { result, buffer in
            result + Int(buffer.mNumberChannels)
        }

        guard channelCount > 0 else {
            return []
        }

        return (1...channelCount).map { AudioObjectPropertyElement($0) }
    }

    private func hasProperty(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        objectID: AudioObjectID
    ) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        return AudioObjectHasProperty(objectID, &address)
    }

    private func isPropertySettable(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        objectID: AudioObjectID
    ) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var isSettable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(objectID, &address, &isSettable)
        return status == noErr && isSettable.boolValue
    }

    private func readFloat32(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        objectID: AudioObjectID
    ) throws -> Float32 {
        var value: Float32 = 0
        try readValue(&value, selector: selector, scope: scope, element: element, objectID: objectID, message: "音量を取得できませんでした")
        return value
    }

    private func writeFloat32(
        _ value: Float32,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        objectID: AudioObjectID
    ) throws {
        var mutableValue = value
        try writeValue(&mutableValue, selector: selector, scope: scope, element: element, objectID: objectID, message: "音量を変更できませんでした")
    }

    private func readUInt32(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        objectID: AudioObjectID
    ) throws -> UInt32 {
        var value: UInt32 = 0
        try readValue(&value, selector: selector, scope: scope, element: element, objectID: objectID, message: "ミュート状態を取得できませんでした")
        return value
    }

    private func writeUInt32(
        _ value: UInt32,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        objectID: AudioObjectID
    ) throws {
        var mutableValue = value
        try writeValue(&mutableValue, selector: selector, scope: scope, element: element, objectID: objectID, message: "ミュートを変更できませんでした")
    }

    private func readAudioDeviceID(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        objectID: AudioObjectID
    ) throws -> AudioDeviceID {
        var value = AudioDeviceID(0)
        try readValue(&value, selector: selector, scope: scope, element: element, objectID: objectID, message: "現在の出力デバイスを取得できませんでした")
        guard value != 0 else {
            throw AudioManagerError.deviceNotFound
        }

        return value
    }

    private func writeAudioDeviceID(
        _ value: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        objectID: AudioObjectID
    ) throws {
        var mutableValue = value
        try writeValue(&mutableValue, selector: selector, scope: scope, element: element, objectID: objectID, message: "出力デバイスを切り替えられませんでした")
    }

    private func readValue<T>(
        _ value: inout T,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        objectID: AudioObjectID,
        message: String
    ) throws {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(objectID, &address) else {
            throw AudioManagerError.propertyUnavailable(message)
        }

        var dataSize = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else {
            throw AudioManagerError.operationFailed(message, status)
        }
    }

    private func writeValue<T>(
        _ value: inout T,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        objectID: AudioObjectID,
        message: String
    ) throws {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard isPropertySettable(selector: selector, scope: scope, element: element, objectID: objectID) else {
            throw AudioManagerError.propertyUnavailable(message)
        }

        var dataSize = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectSetPropertyData(objectID, &address, 0, nil, dataSize, &value)
        guard status == noErr else {
            throw AudioManagerError.operationFailed(message, status)
        }
    }
}
