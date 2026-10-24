import Foundation
import RelayContextComposition

public struct SessionCardDetail: Equatable, Sendable {
    public let kind:String;public let language:String?;public let text:String
}
public struct SessionCard: Equatable, Sendable {
    public let lead:String;public let points:[String];public let detail:SessionCardDetail?
    init(_ node:JSONNode) throws {
        let o=try node.object(["lead","points","detail"]);lead=try o["lead"]!.string(280)
        points=try o["points"]!.array(2).map { try $0.string(180) }
        if o["detail"]!.isNull { detail=nil;return }
        let d=try o["detail"]!.object(["kind","language","text"]);let kind=try d["kind"]!.string()
        guard ["prose","code"].contains(kind) else { throw PanelBridgeError.malformed }
        let language=d["language"]!.isNull ? nil : try d["language"]!.string()
        guard (kind=="prose" && language==nil) || (kind=="code" && ["python","sql"].contains(language)) else { throw PanelBridgeError.malformed }
        guard case .string(let text)=d["text"]!, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,text.utf8.count<=4096,
              !text.unicodeScalars.contains(where: { disallowedTextScalar($0,code:kind=="code") }) else { throw PanelBridgeError.malformed }
        detail=SessionCardDetail(kind:kind,language:language,text:text)
    }
}
public struct PythonTurnIdentity: Equatable, Sendable {
    public let identifier:String;public let version:UInt64;public let generation:UInt64
}
public struct SessionAnswerDecision: Sendable {
    public let sessionID:UUID;public let epoch:UInt64;public let generation:UInt64;public let requestID:UUID;public let eventSequence:UInt64
    public let resultRevision:UInt64;public let disposition:String;public let reason:String;public let token:PythonTurnIdentity?
    public let displayID:String?;public let question:String;public let answerID:String?;public let answerKind:String?;public let card:SessionCard?
    public let taskContext:TaskContextUse?
    public let responsePreferencesRevision:UUID?
    public init(data:Data) throws {
        let o=try StrictJSON.decode(data).object(["schemaVersion","captureSessionID","sessionEpoch","presentationGeneration","requestID","eventSequence","resultRevision","disposition","reasonCode","pythonToken","displayID","question","answerID","answerKind","card","provenance"])
        guard try o["schemaVersion"]!.uint()==1,
              let session=UUID(uuidString:try o["captureSessionID"]!.string()),let request=UUID(uuidString:try o["requestID"]!.string()) else { throw PanelBridgeError.malformed }
        sessionID=session;requestID=request;epoch=try o["sessionEpoch"]!.uint();generation=try o["presentationGeneration"]!.uint();eventSequence=try o["eventSequence"]!.uint()
        resultRevision=try o["resultRevision"]!.uint();disposition=try o["disposition"]!.string();reason=try o["reasonCode"]!.string(80)
        guard ["pending","answer","clarify","abstain","error"].contains(disposition),resultRevision==(disposition=="pending" ? 1:2) else { throw PanelBridgeError.malformed }
        let noTurn=o["pythonToken"]!.isNull
        if noTurn {
            guard disposition=="abstain",o["displayID"]!.isNull,case .string("")=o["question"]! else { throw PanelBridgeError.malformed }
            token=nil;displayID=nil;question=""
        } else {
            let t=try o["pythonToken"]!.object(["turnID","version","generation"])
            token=PythonTurnIdentity(identifier:try t["turnID"]!.string(256),version:try t["version"]!.uint(false),generation:try t["generation"]!.uint())
            let display=try o["displayID"]!.string(64);displayID=display;question=try o["question"]!.string(500)
            guard display.utf8.allSatisfy({ (48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||[45,46,95].contains($0) }) else { throw PanelBridgeError.malformed }
        }
        if disposition != "answer" {
            guard o["answerID"]!.isNull,o["answerKind"]!.isNull,o["card"]!.isNull,o["provenance"]!.isNull else { throw PanelBridgeError.malformed }
            answerID=nil;answerKind=nil;card=nil;taskContext=nil;responsePreferencesRevision=nil;return
        }
        answerID=try o["answerID"]!.string(64);answerKind=try o["answerKind"]!.string();card=try SessionCard(o["card"]!)
        if answerKind=="reviewed_reference" {
            taskContext=nil;responsePreferencesRevision=nil
            let p=try o["provenance"]!.object(["referenceID","sourceRef"])
            _=try p["referenceID"]!.string(160);_=try p["sourceRef"]!.string(256)
        } else if answerKind=="generated_suggestion" {
            guard case .object(let p)=o["provenance"]! else { throw PanelBridgeError.malformed }
            if p["personal"] != nil {
                taskContext=nil;responsePreferencesRevision=nil
                guard try o["provenance"]!.object(["personal","contextRevision","facts","checks"])["personal"]!.boolean() else { throw PanelBridgeError.malformed }
                _=try p["contextRevision"]!.string(256)
                let facts=try p["facts"]!.array(2);guard !facts.isEmpty else { throw PanelBridgeError.malformed }
                for fact in facts {
                    let f=try fact.object(["factID","sourceID","actor","revision"])
                    _=try f["factID"]!.string(256);_=try f["sourceID"]!.string(256);_=try f["revision"]!.uint(false)
                    guard ["self","team","teammate"].contains(try f["actor"]!.string()) else { throw PanelBridgeError.malformed }
                }
                guard try p["checks"]!.array(1).map({try $0.string()})==["host_exact_approved_facts"] else { throw PanelBridgeError.malformed }
            } else {
                var keys:Set<String>=["model","checks","independentlyReviewed"]
                if p["taskContext"] != nil{keys.insert("taskContext")}
                if let revision=p["responsePreferencesRevision"]{
                    keys.insert("responsePreferencesRevision")
                    guard let value=UUID(uuidString:try revision.string(36)) else{throw PanelBridgeError.malformed}
                    responsePreferencesRevision=value
                }else{responsePreferencesRevision=nil}
                _=try o["provenance"]!.object(keys)
                if let context=p["taskContext"] {
                    guard case .object(let fields)=context else{throw PanelBridgeError.malformed}
                    let c=try context.object(fields["imageDigest"]==nil ? ["provenance","source","capturedUptimeNanoseconds"]:["provenance","source","capturedUptimeNanoseconds","imageDigest"])
                    let provenance=try c["provenance"]!.string()
                    guard ["local_ocr","selected_accessibility_text"].contains(provenance) else { throw PanelBridgeError.malformed }
                    var imageDigest:String?
                    if let digest=c["imageDigest"] {
                        let value=try digest.string(64)
                        guard provenance=="local_ocr",value.utf8.count==64,value.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{throw PanelBridgeError.malformed}
                        imageDigest=value
                    }
                    taskContext=TaskContextUse(provenance:provenance,source:try c["source"]!.string(160),capturedUptimeNanoseconds:try c["capturedUptimeNanoseconds"]!.uint(),imageDigest:imageDigest)
                } else { taskContext=nil }
                _=try p["model"]!.string(120);guard try !p["independentlyReviewed"]!.boolean() else { throw PanelBridgeError.malformed }
                let checks=try p["checks"]!.array(3).map { try $0.string(80) }
                guard checks.contains("format_checked"),checks.allSatisfy({ ["format_checked","python_syntax_checked"].contains($0) }) else { throw PanelBridgeError.malformed }
            }
        } else { throw PanelBridgeError.malformed }
    }
}
