import Foundation

protocol SpeechAssetDownloading:Sendable {
    func download(_ artifact:SpeechAssetArtifact,to destination:URL,deadline:UInt64,
                  progress:@escaping @Sendable(UInt64)->Void)async throws
}

private enum SpeechDownloadFailure:Error {
    case response(Int,TimeInterval?),invalidArtifact,expired,network(Int)
}

/// A foreground public-asset transport. Configuration is copied and stripped
/// of credential/cookie storage; no model registry or account provider is used.
final class SpeechAssetDownloader:@unchecked Sendable,SpeechAssetDownloading {
    private let configuration:URLSessionConfiguration
    private let sleep:@Sendable(TimeInterval)async throws->Void
    init(configuration:URLSessionConfiguration = .ephemeral,
         sleep:@escaping @Sendable(TimeInterval)async throws->Void = {try await Task.sleep(for:.seconds($0))}){
        let copy=configuration.copy() as! URLSessionConfiguration
        copy.httpShouldSetCookies=false;copy.httpCookieStorage=nil;copy.urlCredentialStorage=nil
        copy.httpAdditionalHeaders=nil;copy.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.configuration=copy;self.sleep=sleep
    }
    func download(_ artifact:SpeechAssetArtifact,to destination:URL,deadline:UInt64,
                  progress:@escaping @Sendable(UInt64)->Void)async throws{
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath:destination.path) else{throw SpeechSetupError.unsafeCache}
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let now=DispatchTime.now().uptimeNanoseconds
            guard now<deadline else{throw SpeechSetupError.downloadUnavailable}
            let config=configuration.copy() as! URLSessionConfiguration
            let remaining=Double(deadline-now)/1_000_000_000
            config.timeoutIntervalForRequest=min(30,max(0.01,remaining))
            config.timeoutIntervalForResource=min(300,max(0.01,remaining))
            let transfer=SpeechDownloadTransfer(artifact:artifact,destination:destination,deadline:deadline,progress:progress)
            do{try await transfer.run(configuration:config);return}
            catch{
                if transfer.didMoveFile {
                    do{try FileManager.default.removeItem(at:destination)}catch{throw SpeechSetupError.unsafeCache}
                }
                if error is CancellationError || Task.isCancelled{throw CancellationError()}
                if let failure=error as? SpeechDownloadFailure {
                    let delay:TimeInterval?
                    switch failure {
                    case .response(let status,let requested):
                        delay=[408,429,500,502,503,504].contains(status) ? min(30,max(0,requested ?? pow(2,Double(attempt)))):nil
                    case .network(let code):
                        if code==URLError.notConnectedToInternet.rawValue{throw SpeechSetupError.offline}
                        delay=[URLError.timedOut,.cannotFindHost,.cannotConnectToHost,.networkConnectionLost,.dnsLookupFailed].map(\.rawValue).contains(code) ? pow(2,Double(attempt)):nil
                    case .invalidArtifact:throw SpeechSetupError.invalidArtifacts
                    case .expired:throw SpeechSetupError.downloadUnavailable
                    }
                    if let delay,attempt<2 {
                        let now=DispatchTime.now().uptimeNanoseconds
                        guard now<deadline,delay<Double(deadline-now)/1_000_000_000 else{throw SpeechSetupError.downloadUnavailable}
                        progress(0);try await sleep(delay);continue
                    }
                }else if let error=error as? SpeechSetupError{throw error}
                throw SpeechSetupError.downloadUnavailable
            }
        }
        throw SpeechSetupError.downloadUnavailable
    }
}

/// The delegate owns the continuation through actual task completion. A
/// pre-registration cancellation is latched, never followed by task.resume().
private final class SpeechDownloadTransfer:NSObject,URLSessionDownloadDelegate,@unchecked Sendable {
    private let artifact:SpeechAssetArtifact
    private let destination:URL
    private let deadline:UInt64
    private let progress:@Sendable(UInt64)->Void
    private let lock=NSLock()
    private var continuation:CheckedContinuation<Void,any Error>?
    private var task:URLSessionDownloadTask?
    private var session:URLSession?
    private var cancelled=false,finished=false,moved=false
    private var failure:(any Error)?
    init(artifact:SpeechAssetArtifact,destination:URL,deadline:UInt64,progress:@escaping @Sendable(UInt64)->Void){
        self.artifact=artifact;self.destination=destination;self.deadline=deadline;self.progress=progress
    }
    var didMoveFile:Bool{lock.withLock{moved}}
    func run(configuration:URLSessionConfiguration)async throws{
        try Task.checkCancellation()
        try await withTaskCancellationHandler{
            try await withCheckedThrowingContinuation{(continuation:CheckedContinuation<Void,any Error>) in
                lock.withLock{self.continuation=continuation}
                let session=URLSession(configuration:configuration,delegate:self,delegateQueue:nil)
                var request=URLRequest(url:artifact.url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:configuration.timeoutIntervalForRequest)
                request.setValue("application/octet-stream",forHTTPHeaderField:"Accept")
                request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
                let task=session.downloadTask(with:request)
                let start=lock.withLock{self.session=session;self.task=task;return !cancelled}
                if start{task.resume()}else{task.cancel();session.invalidateAndCancel();finish(.failure(CancellationError()))}
            }
        }onCancel:{self.cancel()}
    }
    private func cancel(){
        let active=lock.withLock{cancelled=true;return task};active?.cancel()
    }
    private func reject(_ error:any Error){
        let active=lock.withLock{if failure==nil{failure=error};return task};active?.cancel()
    }
    private func finish(_ result:Result<Void,any Error>){
        let owned=lock.withLock{()->(CheckedContinuation<Void,any Error>?,URLSession?) in
            guard !finished else{return(nil,nil)};finished=true
            let pending=continuation,session=self.session;continuation=nil;task=nil;self.session=nil
            return(pending,session)
        }
        owned.1?.finishTasksAndInvalidate();owned.0?.resume(with:result)
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64){
        guard totalBytesWritten>=0,UInt64(totalBytesWritten)<=artifact.byteCount,
              totalBytesExpectedToWrite<=0 || UInt64(totalBytesExpectedToWrite)<=artifact.byteCount else{reject(SpeechDownloadFailure.invalidArtifact);return}
        guard DispatchTime.now().uptimeNanoseconds<deadline else{reject(SpeechDownloadFailure.expired);return}
        progress(UInt64(totalBytesWritten))
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL){
        do{
            try Task.checkCancellation()
            guard !lock.withLock({cancelled}) else{throw CancellationError()}
            guard DispatchTime.now().uptimeNanoseconds<deadline else{throw SpeechDownloadFailure.expired}
            guard let response=downloadTask.response as? HTTPURLResponse else{throw SpeechDownloadFailure.invalidArtifact}
            guard response.statusCode==200 else{throw SpeechDownloadFailure.response(response.statusCode,Self.retryAfter(response.value(forHTTPHeaderField:"Retry-After")))}
            guard response.mimeType?.lowercased() != "text/html" else{throw SpeechDownloadFailure.invalidArtifact}
            let size=(try FileManager.default.attributesOfItem(atPath:location.path)[.size] as? NSNumber)?.uint64Value
            guard size==artifact.byteCount else{throw SpeechDownloadFailure.invalidArtifact}
            let handle=try FileHandle(forReadingFrom:location)
            let prefix=try handle.read(upToCount:512) ?? Data();try handle.close()
            let text=String(decoding:prefix,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
            guard !text.hasPrefix("<!doctype html"),!text.hasPrefix("<html") else{throw SpeechDownloadFailure.invalidArtifact}
            try FileManager.default.moveItem(at:location,to:destination)
            lock.withLock{moved=true};progress(artifact.byteCount)
        }catch{lock.withLock{if failure==nil{failure=error}}}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:(any Error)?){
        let state=lock.withLock{(cancelled,failure,moved)}
        if state.0{finish(.failure(CancellationError()))}
        else if let failure=state.1{finish(.failure(failure))}
        else if let error {
            let value=error as NSError
            finish(.failure(SpeechDownloadFailure.network(value.domain==NSURLErrorDomain ? value.code:URLError.unknown.rawValue)))
        }else if state.2{finish(.success(()))}
        else{finish(.failure(SpeechDownloadFailure.invalidArtifact))}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping @Sendable(URLRequest?)->Void){
        guard request.url?.scheme?.lowercased()=="https" else{reject(SpeechDownloadFailure.invalidArtifact);completionHandler(nil);return}
        var publicRequest=request
        for header in ["Authorization","Cookie","Proxy-Authorization"]{publicRequest.setValue(nil,forHTTPHeaderField:header)}
        completionHandler(publicRequest)
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didReceive challenge:URLAuthenticationChallenge,completionHandler:@escaping @Sendable(URLSession.AuthChallengeDisposition,URLCredential?)->Void){
        completionHandler(challenge.protectionSpace.authenticationMethod==NSURLAuthenticationMethodServerTrust ? .performDefaultHandling:.cancelAuthenticationChallenge,nil)
    }
    private static func retryAfter(_ value:String?)->TimeInterval?{
        guard let value else{return nil}
        if let seconds=TimeInterval(value),seconds.isFinite{return min(30,max(0,seconds))}
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(secondsFromGMT:0);formatter.dateFormat="EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from:value).map{min(30,max(0,$0.timeIntervalSinceNow))}
    }
}
