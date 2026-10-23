import Foundation
import Combine

actor ReviewGate {
    var pending:[CheckedContinuation<PreparedSpeechAssets,Never>]=[]
    var calls=0
    func prepare()async->PreparedSpeechAssets {
        calls+=1
        return await withCheckedContinuation{pending.append($0)}
    }
    func release() {
        let values=pending;pending=[]
        values.forEach{$0.resume(returning:PreparedSpeechAssets(manifestID:"synthetic",asrModelRoot:URL(fileURLWithPath:"/private/tmp/never-loaded"),vadCompiledModel:URL(fileURLWithPath:"/private/tmp/never-loaded/vad")))}
    }
}
@main struct CoordinatorProbe {
    @MainActor static func main()async throws {
        for iteration in 0..<10 {
            let gate=ReviewGate(),setup=SpeechSetupCoordinator(prepare:{_ in await gate.prepare()})
            var oldWaiter:Task<PreparedSpeechAssets,any Error>?
            var replacement:Task<PreparedSpeechAssets,any Error>?
            var launched=false
            let observer=setup.$snapshot.sink{snapshot in
                if snapshot.stage == .ready && !launched {
                    launched=true
                    replacement=Task(priority:.high){try await setup.prepare()}
                    oldWaiter?.cancel()
                }
            }
            let first=Task(priority:.high){try await setup.prepare()}
            oldWaiter=Task(priority:.background){try await setup.prepare()}
            while await gate.calls<1 {await Task.yield()}
            for _ in 0..<10{await Task.yield()}
            await gate.release();_ = await first.result
            for _ in 0..<1000 {
                let calls=await gate.calls
                if setup.snapshot.stage == .cancelled || calls>=2{break}
                await Task.yield()
            }
            for _ in 0..<20{await Task.yield()}
            print("iteration=\(iteration) replacement_started=\(await gate.calls>=2) replacement_state=\(setup.snapshot.stage) busy=\(setup.snapshot.isBusy)")
            setup.cancel();await gate.release();_ = await oldWaiter?.result;_ = await replacement?.result
            observer.cancel()
        }
    }
}
