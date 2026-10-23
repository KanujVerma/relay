import Foundation

func disallowedTextScalar(_ scalar:Unicode.Scalar,code:Bool=false) -> Bool {
    if code && [9,10].contains(scalar.value) { return false }
    switch scalar.properties.generalCategory {
    case .control,.format,.surrogate,.lineSeparator,.paragraphSeparator:return true
    default:return false
    }
}

public enum PanelBridgeError: Error { case malformed, overflow, closed, timedOut }
public indirect enum JSONNode: Sendable {
    case object([String:JSONNode]), array([JSONNode]), string(String), number(String), bool(Bool), null
    func object(_ keys: Set<String>) throws -> [String:JSONNode] {
        guard case .object(let v)=self, Set(v.keys)==keys else { throw PanelBridgeError.malformed }; return v
    }
    func string(_ limit: Int=512) throws -> String {
        guard case .string(let v)=self, !v.isEmpty, v.utf8.count<=limit,
              !v.unicodeScalars.contains(where: { disallowedTextScalar($0) }) else { throw PanelBridgeError.malformed };return v
    }
    func uint(_ positive: Bool=true) throws -> UInt64 {
        guard case .number(let text)=self, !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let v=UInt64(text), !positive || v>0 else { throw PanelBridgeError.malformed };return v
    }
    var isNull: Bool { if case .null=self { return true };return false }
    func boolean() throws -> Bool { guard case .bool(let v)=self else { throw PanelBridgeError.malformed };return v }
    func array(_ count: Int) throws -> [JSONNode] { guard case .array(let v)=self,v.count<=count else { throw PanelBridgeError.malformed };return v }
}

/// Small strict preflight parser: duplicate fields, depth and UTF-8 are rejected
/// before typed decoding. Counters are parsed from their original decimal bytes.
public enum StrictJSON {
    public static func decode(_ data: Data) throws -> JSONNode {
        guard !data.isEmpty,data.count<=16384,String(data:data,encoding:.utf8) != nil else { throw PanelBridgeError.overflow }
        var parser=Parser(bytes:Array(data));let value=try parser.value(0);parser.space()
        guard parser.index==parser.bytes.count else { throw PanelBridgeError.malformed };return value
    }
    private struct Parser {
        let bytes:[UInt8];var index=0
        mutating func space() { while index<bytes.count && [9,10,13,32].contains(bytes[index]) { index+=1 } }
        mutating func consume(_ b: UInt8) throws { space();guard index<bytes.count,bytes[index]==b else { throw PanelBridgeError.malformed };index+=1 }
        mutating func text() throws -> String {
            space();let start=index;try consume(34);var escaped=false
            while index<bytes.count {
                let b=bytes[index];index+=1
                if !escaped && b==34 { return try JSONDecoder().decode(String.self,from:Data(bytes[start..<index])) }
                if !escaped && b<32 { throw PanelBridgeError.malformed }
                if escaped { escaped=false } else if b==92 { escaped=true }
            }
            throw PanelBridgeError.malformed
        }
        mutating func value(_ depth:Int) throws -> JSONNode {
            guard depth<=12 else { throw PanelBridgeError.overflow };space();guard index<bytes.count else { throw PanelBridgeError.malformed }
            let b=bytes[index]
            if b==34 { return .string(try text()) }
            if b==123 {
                index+=1;space();var result:[String:JSONNode]=[:]
                if index<bytes.count && bytes[index]==125 { index+=1;return .object(result) }
                while true {
                    let key=try text();guard result[key]==nil else { throw PanelBridgeError.malformed };try consume(58)
                    result[key]=try value(depth+1);space();guard index<bytes.count else { throw PanelBridgeError.malformed }
                    if bytes[index]==125 { index+=1;return .object(result) };try consume(44)
                }
            }
            if b==91 {
                index+=1;space();var result:[JSONNode]=[]
                if index<bytes.count && bytes[index]==93 { index+=1;return .array(result) }
                while true {
                    guard result.count<64 else { throw PanelBridgeError.overflow };result.append(try value(depth+1));space()
                    guard index<bytes.count else { throw PanelBridgeError.malformed }
                    if bytes[index]==93 { index+=1;return .array(result) };try consume(44)
                }
            }
            for (literal,node) in [("true",JSONNode.bool(true)),("false",.bool(false)),("null",.null)] {
                let token=Array(literal.utf8)
                if bytes[index...].starts(with:token) { index+=token.count;return node }
            }
            let start=index
            while index<bytes.count && ![9,10,13,32,44,93,125].contains(bytes[index]) { index+=1 }
            guard start<index else { throw PanelBridgeError.malformed }
            let raw=String(decoding:bytes[start..<index],as:UTF8.self)
            guard raw.range(of:#"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#,options:.regularExpression) != nil else { throw PanelBridgeError.malformed }
            return .number(raw)
        }
    }
}

public final class AnswerFrameDecoder {
    private var buffer=Data();private var expected:Int?
    public init() {}
    public var hasPartial:Bool { !buffer.isEmpty || expected != nil }
    public func feed(_ chunk:Data) throws -> [Data] {
        guard chunk.count<=32768 else { throw PanelBridgeError.overflow };buffer.append(chunk);var frames:[Data]=[]
        while true {
            if expected==nil {
                guard buffer.count>=4 else { break }
                let length=buffer.prefix(4).reduce(0) { ($0<<8)|Int($1) };buffer.removeFirst(4)
                guard (1...16384).contains(length) else { throw PanelBridgeError.overflow };expected=length
            }
            guard let length=expected,buffer.count>=length else { break }
            frames.append(Data(buffer.prefix(length)));buffer.removeFirst(length);expected=nil
        }
        return frames
    }
    public func finish() throws { guard !hasPartial else { throw PanelBridgeError.malformed } }
}
