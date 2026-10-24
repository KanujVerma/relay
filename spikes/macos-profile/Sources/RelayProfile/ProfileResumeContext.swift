import CryptoKit
import Foundation

enum ProfileResumeValidation {
    struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    static func keys(_ decoder: Decoder, _ expected: Set<String>) throws {
        let container = try decoder.container(keyedBy: Key.self)
        guard Set(container.allKeys.map(\.stringValue)) == expected else { throw ProfileError.invalidPayload }
    }
    static func hex(_ value: String, count: Int = 64) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func text(_ value: String, scalars: Int, bytes: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        value.unicodeScalars.count <= scalars && value.utf8.count <= bytes &&
        !value.unicodeScalars.contains { [.control, .format, .surrogate, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory) }
    }
    static func span(_ start: Int, _ end: Int, text: String) -> Bool {
        // Python's selected-text offsets count Unicode code points. Swift
        // Character/grapheme and UTF-16 counts have different boundaries.
        start >= 0 && end > start && end <= 30_000 && end-start == text.unicodeScalars.count
    }
    static func location(_ value: String) -> Bool {
        value.utf8.count <= 80 && value.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 58 } &&
        value.range(of: "^(text:line|pdf:page|docx:paragraph):[1-9][0-9]*$", options: .regularExpression) != nil
    }
}

public struct ProfileResumeField: Decodable, Sendable, Equatable, Identifiable {
    public var id: String { kind }
    public let kind: String
    public let text: String
    public let sha256: String
    public let spanStart: Int
    public let spanEnd: Int
    public let locator: String
    enum CodingKeys: String, CodingKey { case kind, text, sha256, spanStart = "span_start", spanEnd = "span_end", locator }
    public init(from decoder: Decoder) throws {
        try ProfileResumeValidation.keys(decoder, ["kind","text","sha256","span_start","span_end","locator"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind); text = try c.decode(String.self, forKey: .text)
        sha256 = try c.decode(String.self, forKey: .sha256)
        spanStart = try c.decode(Int.self, forKey: .spanStart); spanEnd = try c.decode(Int.self, forKey: .spanEnd)
        locator = try c.decode(String.self, forKey: .locator)
        guard ["section_heading","employer","title","institution","credential","project","date","category","issuer","gpa","status"].contains(kind),
              ProfileResumeValidation.text(text, scalars: 160, bytes: 512),
              ProfileResumeValidation.span(spanStart, spanEnd, text: text),
              ProfileResumeValidation.location(locator), sha256 == ProfileResumeValidation.hash(text)
        else { throw ProfileError.invalidPayload }
    }
    public var label: String {
        ["section_heading":"Section", "employer":"Employer", "title":"Role", "institution":"Institution",
         "credential":"Credential", "project":"Project", "date":"Dates as written", "category":"Category",
         "issuer":"Issuer", "gpa":"GPA as written", "status":"Status as written"][kind] ?? "Context"
    }
}

public struct ProfileResumeContext: Decodable, Sendable, Equatable {
    public let section: String
    public let entryID: String
    public let fields: [ProfileResumeField]
    enum CodingKeys: String, CodingKey { case section, entryID = "entry_id", fields }
    public init(from decoder: Decoder) throws {
        try ProfileResumeValidation.keys(decoder, ["section","entry_id","fields"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        section = try c.decode(String.self, forKey: .section); entryID = try c.decode(String.self, forKey: .entryID)
        fields = try c.decode([ProfileResumeField].self, forKey: .fields)
        guard ["education","experience","projects","skills","certifications","summary","other"].contains(section),
              ProfileResumeValidation.hex(entryID, count: 32), fields.count <= 6,
              Set(fields.map(\.kind)).count == fields.count else { throw ProfileError.invalidPayload }
    }
}

public struct ProfileResumeCoverage: Decodable, Sendable {
    public let version: Int
    public let unclassifiedLines: Int
    public let codes: [String]
    enum CodingKeys: String, CodingKey { case version, unclassifiedLines = "unclassified_lines", codes }
    public init(from decoder: Decoder) throws {
        try ProfileResumeValidation.keys(decoder, ["version","unclassified_lines","codes"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        unclassifiedLines = try c.decode(Int.self, forKey: .unclassifiedLines); codes = try c.decode([String].self, forKey: .codes)
        guard version == 2, (0...30_000).contains(unclassifiedLines), codes.count <= 4, Set(codes).count == codes.count,
              codes.allSatisfy({ ["unclassified_text","ambiguous_entry","line_budget","unsupported_layout"].contains($0) })
        else { throw ProfileError.invalidPayload }
    }
}
