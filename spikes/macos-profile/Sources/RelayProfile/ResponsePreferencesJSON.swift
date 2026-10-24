import Foundation

// Domain-local reuse of RelaySessionPanel.StrictJSON: same duplicate-key and
// decimal-byte validation, with the approved32KiB catalog/eight-level bounds.
indirect enum PreferenceJSONNode: Sendable {
    case object([String:PreferenceJSONNode]), array([PreferenceJSONNode]), string(String), number(String), bool(Bool), null
    func object(_ keys: Set<String>) throws -> [String:PreferenceJSONNode] {
        guard case .object(let v)=self, Set(v.keys)==keys else { throw ResponsePreferencesError.invalidCatalog }; return v
    }
    func string(_ limit: Int=512) throws -> String {
        guard case .string(let v)=self, !v.isEmpty, v.utf8.count<=limit,
              !v.unicodeScalars.contains(where: { preferenceDisallowedScalar($0) }) else { throw ResponsePreferencesError.invalidCatalog };return v
    }
    func uint(_ positive: Bool=true) throws -> UInt64 {
        guard case .number(let text)=self, !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let v=UInt64(text), !positive || v>0 else { throw ResponsePreferencesError.invalidCatalog };return v
    }
    var isNull: Bool { if case .null=self { return true };return false }
    func boolean() throws -> Bool { guard case .bool(let v)=self else { throw ResponsePreferencesError.invalidCatalog };return v }
    func array(_ count: Int) throws -> [PreferenceJSONNode] { guard case .array(let v)=self,v.count<=count else { throw ResponsePreferencesError.invalidCatalog };return v }
}

/// Small strict preflight parser: duplicate fields, depth and UTF-8 are rejected
/// before typed decoding. Counters are parsed from their original decimal bytes.
enum PreferenceJSON {
    static func decode(_ data: Data) throws -> PreferenceJSONNode {
        guard !data.isEmpty,data.count<=32768,String(data:data,encoding:.utf8) != nil else { throw ResponsePreferencesError.invalidCatalog }
        var parser=Parser(bytes:Array(data));let value=try parser.value(0);parser.space()
        guard parser.index==parser.bytes.count else { throw ResponsePreferencesError.invalidCatalog };return value
    }
    private struct Parser {
        let bytes:[UInt8];var index=0
        mutating func space() { while index<bytes.count && [9,10,13,32].contains(bytes[index]) { index+=1 } }
        mutating func consume(_ b: UInt8) throws { space();guard index<bytes.count,bytes[index]==b else { throw ResponsePreferencesError.invalidCatalog };index+=1 }
        mutating func text() throws -> String {
            space();let start=index;try consume(34);var escaped=false
            while index<bytes.count {
                let b=bytes[index];index+=1
                if !escaped && b==34 { return try JSONDecoder().decode(String.self,from:Data(bytes[start..<index])) }
                if !escaped && b<32 { throw ResponsePreferencesError.invalidCatalog }
                if escaped { escaped=false } else if b==92 { escaped=true }
            }
            throw ResponsePreferencesError.invalidCatalog
        }
        mutating func value(_ depth:Int) throws -> PreferenceJSONNode {
            guard depth<=8 else { throw ResponsePreferencesError.invalidCatalog };space();guard index<bytes.count else { throw ResponsePreferencesError.invalidCatalog }
            let b=bytes[index]
            if b==34 { return .string(try text()) }
            if b==123 {
                index+=1;space();var result:[String:PreferenceJSONNode]=[:]
                if index<bytes.count && bytes[index]==125 { index+=1;return .object(result) }
                while true {
                    let key=try text();guard result[key]==nil else { throw ResponsePreferencesError.invalidCatalog };try consume(58)
                    result[key]=try value(depth+1);space();guard index<bytes.count else { throw ResponsePreferencesError.invalidCatalog }
                    if bytes[index]==125 { index+=1;return .object(result) };try consume(44)
                }
            }
            if b==91 {
                index+=1;space();var result:[PreferenceJSONNode]=[]
                if index<bytes.count && bytes[index]==93 { index+=1;return .array(result) }
                while true {
                    guard result.count<64 else { throw ResponsePreferencesError.invalidCatalog };result.append(try value(depth+1));space()
                    guard index<bytes.count else { throw ResponsePreferencesError.invalidCatalog }
                    if bytes[index]==93 { index+=1;return .array(result) };try consume(44)
                }
            }
            for (literal,node) in [("true",PreferenceJSONNode.bool(true)),("false",.bool(false)),("null",.null)] {
                let token=Array(literal.utf8)
                if bytes[index...].starts(with:token) { index+=token.count;return node }
            }
            let start=index
            while index<bytes.count && ![9,10,13,32,44,93,125].contains(bytes[index]) { index+=1 }
            guard start<index else { throw ResponsePreferencesError.invalidCatalog }
            let raw=String(decoding:bytes[start..<index],as:UTF8.self)
            guard raw.range(of:#"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#,options:.regularExpression) != nil else { throw ResponsePreferencesError.invalidCatalog }
            return .number(raw)
        }
    }
}

