import AppKit
import CoreAudio
import Foundation

/// A deliberately narrow selected-app source. Never falls back to global audio.
/// Uses the public Core Audio process list. Adapted from MIT SystemAudioKit
/// AudioProcesses.swift, revision ccc6ab1e53b27e16b2eb4c01890560568a73d38c.
public enum SelectedAppProcesses {
    /// Validate explicit bundle ID, not an arbitrary substring/glob.
    public static func isValidBundleID(_ name: String) -> Bool {
        guard name.count >= 3, name.count <= 180,
              name.contains("."), !name.hasPrefix("."), !name.hasSuffix(".")
        else { return false }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { c in
                c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_")
            }
        }
    }

    /// Known helper process IDs reported by macOS; exact matching only.
    /// The selected app *may* include other browser tabs' audio, not just Meet.
    public static func parentBundleID(_ bundle: String) -> String {
        for suffixMarker in [
            ".helper", ".Helper", ".WebContent",
            ".GPU", ".Networking", ".renderer"
        ] {
            if let range = bundle.range(of: suffixMarker) {
                // Only real helper-component boundaries, not arbitrary
                // substrings such as ".helperAttacker".
                let remainder = bundle[range.upperBound...]
                if remainder.isEmpty || remainder.first == "." {
                    return String(bundle[..<range.lowerBound])
                }
            }
        }
        return bundle
    }

    public static func isSelected(
        _ selected: String, processBundleID: String?,
        owningBundleID: String?
    ) -> Bool {
        guard isValidBundleID(selected) else { return false }
        // When the OS supplies a regular owner app, never let a spoofed
        // helper bundle name override that different ownership.
        if let owningBundleID {
            return owningBundleID == selected
        }
        guard let processBundleID else { return false }
        return processBundleID == selected
            || parentBundleID(processBundleID) == selected
    }

    public static func bundleIDs() -> [String] {
        let records = processRecords()
        return Array(Set(records.compactMap { record in
            let raw = record.reportedBundleID
            return record.ownerBundleID ?? raw.map(parentBundleID)
        }.filter(isValidBundleID))).sorted()
    }

    /// Includes all known audio helper processes for this app, never other apps.
    static func objectIDs(for selected: String) -> [AudioObjectID] {
        guard isValidBundleID(selected) else { return [] }
        return processRecords().filter {
            isSelected(selected, processBundleID: $0.reportedBundleID,
                       owningBundleID: $0.ownerBundleID)
        }.map(\.objectID).sorted()
    }

    private struct Record {
        let objectID: AudioObjectID
        let reportedBundleID: String?
        let ownerBundleID: String?
    }

    private static func processRecords() -> [Record] {
        let all = (try? AudioObjectID.tapSystem.tapReadArray(
            kAudioHardwarePropertyProcessObjectList, default: AudioObjectID(0)
        )) ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return all.compactMap { object in
            guard let pid = try? object.tapRead(
                kAudioProcessPropertyPID, default: pid_t(-1)
            ), pid > 0, pid != ownPID else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            let owner = app?.activationPolicy == .regular
                ? app?.bundleIdentifier : nil
            return Record(
                objectID: object,
                reportedBundleID: object.tapReadString(kAudioProcessPropertyBundleID),
                ownerBundleID: owner
            )
        }
    }
}
