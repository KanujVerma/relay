import Foundation
@main struct CacheReadProbe {
    static func main()throws {
        let store=try SpeechAssetStore(directory:URL(fileURLWithPath:"/private/tmp/relay-auto-speech-real-cache"))
        guard let assets=try store.cachedAssets() else{fatalError("previous public cache failed full validation")}
        print("readonly_cache_verified manifest=\(assets.manifestID) files=\(SpeechAssetManifest.managedDefault.artifacts.count) bytes=\(assets.byteCount ?? 0)")
    }
}
