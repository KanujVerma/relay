import CoreAudio
import Foundation

// Selected public property access patterns adapted from MIT SystemAudioKit,
// revision ccc6ab1e53b27e16b2eb4c01890560568a73d38c.
// Attribution and full MIT notice: ../../THIRD_PARTY_NOTICES.md

struct TapAudioError: LocalizedError {
    let action: String
    let status: OSStatus

    var errorDescription: String? {
        "\(action) failed (Core Audio OSStatus \(status))."
    }
}

@inline(__always)
func tapCheck(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else { throw TapAudioError(action: action, status: status) }
}

func tapAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

extension AudioObjectID {
    static let tapSystem = AudioObjectID(kAudioObjectSystemObject)
    static let tapUnknown = AudioObjectID(kAudioObjectUnknown)

    func tapRead<T: BitwiseCopyable>(
        _ selector: AudioObjectPropertySelector,
        default initial: T
    ) throws -> T {
        var address = tapAddress(selector)
        var result = initial
        var size = UInt32(MemoryLayout<T>.size)
        try tapCheck(AudioObjectGetPropertyData(
            self, &address, 0, nil, &size, &result
        ), "Reading Core Audio property")
        return result
    }

    func tapReadArray<T: BitwiseCopyable>(
        _ selector: AudioObjectPropertySelector, default item: T
    ) throws -> [T] {
        var address = tapAddress(selector)
        var bytes: UInt32 = 0
        try tapCheck(AudioObjectGetPropertyDataSize(
            self, &address, 0, nil, &bytes
        ), "Sizing Core Audio property array")
        let count = Int(bytes) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        var result = [T](repeating: item, count: count)
        try tapCheck(AudioObjectGetPropertyData(
            self, &address, 0, nil, &bytes, &result
        ), "Reading Core Audio property array")
        return Array(result.prefix(Int(bytes) / MemoryLayout<T>.stride))
    }

    func tapReadString(_ selector: AudioObjectPropertySelector) -> String? {
        var address = tapAddress(selector)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(
            self, &address, 0, nil, &size, &cf
        ) == noErr, let retained = cf?.takeRetainedValue() else { return nil }
        return retained as String
    }
}
