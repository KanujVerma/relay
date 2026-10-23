import Foundation

/// Immutable public dependency identity; no mutable registry or auth is consulted.
struct SpeechAssetArtifact:Sendable,Equatable {
    let repository:String
    let revision:String
    let remotePath:String
    let localPath:String
    let byteCount:UInt64
    let sha256:String
    var url:URL { URL(string:"https://huggingface.co/\(repository)/resolve/\(revision)/\(remotePath)")! }
}

struct SpeechAssetManifest:Sendable,Equatable {
    let id:String
    let artifacts:[SpeechAssetArtifact]
    let totalBytes:UInt64
    static let maximumBytes:UInt64=256*1024*1024
    static let asrDirectory="parakeet-eou-streaming/320ms"
    static let vadDirectory="silero-vad-unified-256ms-v6.2.1.mlmodelc"
    init(id:String,artifacts:[SpeechAssetArtifact])throws {
        guard !id.isEmpty,id.utf8.count<=80,id.utf8.allSatisfy({(97...122).contains($0)||(48...57).contains($0)||$0==45}),
              !artifacts.isEmpty,artifacts.count<=64,Set(artifacts.map(\.localPath)).count==artifacts.count else{throw SpeechSetupError.invalidManifest}
        var total:UInt64=0
        for item in artifacts {
            guard ["FluidInference/parakeet-realtime-eou-120m-coreml","FluidInference/silero-vad-coreml"].contains(item.repository),
                  Self.hex(item.revision,count:40),Self.hex(item.sha256,count:64),Self.safePath(item.remotePath),Self.safePath(item.localPath),
                  item.byteCount>0,item.byteCount<=Self.maximumBytes else{throw SpeechSetupError.invalidManifest}
            let (next,overflow)=total.addingReportingOverflow(item.byteCount)
            guard !overflow,next<=Self.maximumBytes else{throw SpeechSetupError.invalidManifest};total=next
        }
        self.id=id;self.artifacts=artifacts;self.totalBytes=total
    }
    static func safePath(_ path:String)->Bool {
        !path.isEmpty && path.utf8.count<=240 && path.split(separator:"/",omittingEmptySubsequences:false).allSatisfy{
            !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.allSatisfy{(65...90).contains($0)||(97...122).contains($0)||(48...57).contains($0)||[45,46,95].contains($0)}
        }
    }
    private static func hex(_ value:String,count:Int)->Bool{value.utf8.count==count && value.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}}
    /// Reviewed NVIDIA Open Model License + MIT assets. These hashes define
    /// dependency policy, never microphone/recording or account consent.
    static let managedDefault=try! SpeechAssetManifest(id:"parakeet-eou320-silero621-v1",artifacts:[
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/decoder.mlmodelc/analytics/coremldata.bin",localPath:"parakeet-eou-streaming/320ms/decoder.mlmodelc/analytics/coremldata.bin",byteCount:243,sha256:"3996975a8cbc1949159c55605b3132b39b2484f51acbd55d796d93c70de02b49"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/decoder.mlmodelc/coremldata.bin",localPath:"parakeet-eou-streaming/320ms/decoder.mlmodelc/coremldata.bin",byteCount:497,sha256:"c3ccbff963d8cf07e2be2bd56ea3384a89ea49628922c6bd95ff62e2ae57dc34"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/decoder.mlmodelc/metadata.json",localPath:"parakeet-eou-streaming/320ms/decoder.mlmodelc/metadata.json",byteCount:3283,sha256:"0977480649f2756894b0acfe2fdf4231a991f25e3fe02562bfb71b65ca944575"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/decoder.mlmodelc/model.mil",localPath:"parakeet-eou-streaming/320ms/decoder.mlmodelc/model.mil",byteCount:7409,sha256:"b7c084a35bdbc887d69d6226cd533e2c11b2792c37d7352cf878f9f6f3c13555"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/decoder.mlmodelc/weights/weight.bin",localPath:"parakeet-eou-streaming/320ms/decoder.mlmodelc/weights/weight.bin",byteCount:7873600,sha256:"0b4cacecdcd9df79ab1e56de67230baf5a8664d2afe0bb8f3408eefa972cb2f4"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/joint_decision.mlmodelc/analytics/coremldata.bin",localPath:"parakeet-eou-streaming/320ms/joint_decision.mlmodelc/analytics/coremldata.bin",byteCount:243,sha256:"5bca32ad130dcad6605cc00044c752aa5b45ef57d14c17f2d1a2fa49d6cf55b5"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/joint_decision.mlmodelc/coremldata.bin",localPath:"parakeet-eou-streaming/320ms/joint_decision.mlmodelc/coremldata.bin",byteCount:493,sha256:"22d4abc4625b935ee035b5f8ce7cb28d1041b9b01c12173e287bf4b5f5d99625"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/joint_decision.mlmodelc/metadata.json",localPath:"parakeet-eou-streaming/320ms/joint_decision.mlmodelc/metadata.json",byteCount:3181,sha256:"e970ae87137730020690d24d971813db3633bbdfed602d43b6a9c84deced6dc8"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/joint_decision.mlmodelc/model.mil",localPath:"parakeet-eou-streaming/320ms/joint_decision.mlmodelc/model.mil",byteCount:9608,sha256:"45e8590bc87e34c162b547e43a4f60e64db15b017f48395d7835a6867884804f"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/joint_decision.mlmodelc/weights/weight.bin",localPath:"parakeet-eou-streaming/320ms/joint_decision.mlmodelc/weights/weight.bin",byteCount:2794182,sha256:"7039b2010a269153f5a96edf28637f921a86ef8822f248f2d6712f7a6bce84b4"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/streaming_encoder.mlmodelc/analytics/coremldata.bin",localPath:"parakeet-eou-streaming/320ms/streaming_encoder.mlmodelc/analytics/coremldata.bin",byteCount:243,sha256:"ae0a559f8d53c43fe13c5c142b15ca237b97812febde71a36475b7b9612baec5"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/streaming_encoder.mlmodelc/coremldata.bin",localPath:"parakeet-eou-streaming/320ms/streaming_encoder.mlmodelc/coremldata.bin",byteCount:670,sha256:"b57dfe32ed2acb0081f97d7a9e410117005823e3d2d995e21feb9e60775443c3"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/streaming_encoder.mlmodelc/metadata.json",localPath:"parakeet-eou-streaming/320ms/streaming_encoder.mlmodelc/metadata.json",byteCount:5327,sha256:"3adc7839db0f5d20b19e2dcd1c009bcf935a7edc61d7473c8150be444bd80488"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/streaming_encoder.mlmodelc/model.mil",localPath:"parakeet-eou-streaming/320ms/streaming_encoder.mlmodelc/model.mil",byteCount:655998,sha256:"eb9d56d7467ad3a8796ec9098b27fb89197638b31e24ede6dd924807d25086e6"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/streaming_encoder.mlmodelc/weights/weight.bin",localPath:"parakeet-eou-streaming/320ms/streaming_encoder.mlmodelc/weights/weight.bin",byteCount:212865856,sha256:"ff553fcb4f4560cfce1e558e16bb9d856e4b4f6a4c08f800d5c126fce4196822"),
        SpeechAssetArtifact(repository:"FluidInference/parakeet-realtime-eou-120m-coreml",revision:"40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355",remotePath:"320ms/vocab.json",localPath:"parakeet-eou-streaming/320ms/vocab.json",byteCount:17437,sha256:"83fd42ad33dae1bd3ceee6c0bb6c625f314cf0b2dc8430be441ac1e2643d5c36"),
        SpeechAssetArtifact(repository:"FluidInference/silero-vad-coreml",revision:"b419383c55c110e2c9271fa6ee0ea83d03c70d96",remotePath:"silero-vad-unified-256ms-v6.2.1.mlmodelc/analytics/coremldata.bin",localPath:"silero-vad-unified-256ms-v6.2.1.mlmodelc/analytics/coremldata.bin",byteCount:243,sha256:"8067594eb3126ab8318af507f0c00cabfed40d5fedb8a0ee5075dd02e903d909"),
        SpeechAssetArtifact(repository:"FluidInference/silero-vad-coreml",revision:"b419383c55c110e2c9271fa6ee0ea83d03c70d96",remotePath:"silero-vad-unified-256ms-v6.2.1.mlmodelc/coremldata.bin",localPath:"silero-vad-unified-256ms-v6.2.1.mlmodelc/coremldata.bin",byteCount:625,sha256:"7db35a4fd995222a7fb0129713473b15d1462572ab4a2e5e4d56bcaad9e40f41"),
        SpeechAssetArtifact(repository:"FluidInference/silero-vad-coreml",revision:"b419383c55c110e2c9271fa6ee0ea83d03c70d96",remotePath:"silero-vad-unified-256ms-v6.2.1.mlmodelc/metadata.json",localPath:"silero-vad-unified-256ms-v6.2.1.mlmodelc/metadata.json",byteCount:3335,sha256:"2740be542c611e1ba358e1849b4e265c65cdf0b17192767e1e5de86a31ac94d6"),
        SpeechAssetArtifact(repository:"FluidInference/silero-vad-coreml",revision:"b419383c55c110e2c9271fa6ee0ea83d03c70d96",remotePath:"silero-vad-unified-256ms-v6.2.1.mlmodelc/model.mil",localPath:"silero-vad-unified-256ms-v6.2.1.mlmodelc/model.mil",byteCount:176918,sha256:"c6a9d1bf22d413265da0a07a1d14151c3ea2fad296b3aa5859275b33ef1c3270"),
        SpeechAssetArtifact(repository:"FluidInference/silero-vad-coreml",revision:"b419383c55c110e2c9271fa6ee0ea83d03c70d96",remotePath:"silero-vad-unified-256ms-v6.2.1.mlmodelc/weights/weight.bin",localPath:"silero-vad-unified-256ms-v6.2.1.mlmodelc/weights/weight.bin",byteCount:882304,sha256:"53ecc8b5081146140ab654c89109cf001f2183abddd7a2411c5081feeffff063")
    ])
}
