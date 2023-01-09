//
//  UploadManager.swift
//  Drund
//
//  Created by Shawna MacNabb on 3/5/19.
//  Copyright © 2019 Drund. All rights reserved.
//

import UIKit
import Photos
import UserNotifications

@objc public protocol UploadRequestManagerDelegate: AnyObject {
    func uploadRequestManagerDidCompleteWithIds(successIds: [Int], request: UploadRequest)
    func uploadRequestManagerDidReceiveProgress(progress: ProgressGroup, request: UploadRequest)
    @objc optional func uploadRequestManagerDidSaveUploadData(fileUploadDataURL: URL, request: UploadRequest)
    @objc optional func uploadRequestManagerUploadStatusChanged(_ status: UploadStatus, request: UploadRequest)
    @objc optional func uploadRequestManagerUpdateBytesSent(request: UploadRequest, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
    @objc optional func uploadRequestManagerDidReceiveError(request: UploadRequest, errorMessage: String?)
    // this is for logging purposes, we need to make a separate framework for logging and after that this will be removed
    @objc optional func uploadRequestManagerLogErrorMessage(request: UploadRequest, _ error: Error, statusCode: Int)
}

class UploadRequestManagerWeakContainer: Any {
    weak var weakUploadRequestDelegate: UploadRequestManagerDelegate?
}

@objc public enum UploadStatus: Int {
    case notUploaded = 0
    case staged = 1
    case inProgress = 2
    case completed = 3
    case failed = 4
    case staging = 5
    case cancelled = 6
}

public class UploadRequestManager: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {

    public static let shared = UploadRequestManager()
    
    private var delegates = [UploadRequestManagerWeakContainer]()
        
    private static var observerContext = 0
    
    var uploadRequestSession: URLSession?
    
    var progresses: [String: ProgressGroup] = [String: ProgressGroup]()
    var uploadRequests: [UploadRequest] = [UploadRequest]()

    var uploadedAlbumIds: [Int] = []
    
    var progressObserver = [NSKeyValueObservation]()
        
    public var backgroundSessionCompletionHander: (() -> Void)?

    override init() {

        super.init()
    }
    
    public func addDelegate(_ listener: UploadRequestManagerDelegate) {
        let container = UploadRequestManagerWeakContainer()
        container.weakUploadRequestDelegate = listener
        self.delegates.append(container)
    }
    
    public func beginBackgroundUpload(uploadRequest: UploadRequest, progress: ProgressGroup) -> ProgressGroup {
        
        let config = URLSessionConfiguration.background(withIdentifier: uploadRequest.requestId)
        config.waitsForConnectivity = true
        uploadRequestSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        
        // todo issue with multiple uploads
        uploadRequests.append(uploadRequest)
        progresses[uploadRequest.requestId] = progress
        
        continueUploadAfterAssetsWrittenToDisk(uploadRequest: uploadRequest, progress: progress)
                
        return progress
    }

    public func beginUpload(uploadRequest: UploadRequest, progress: ProgressGroup) -> ProgressGroup {
        
        // we don't need a background session for this.
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        uploadRequestSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
                
        uploadRequests.append(uploadRequest)
        progresses[uploadRequest.requestId] = progress
        
        FileManagerUtils.writeAssetsToDisk(uploadRequest.assets, completion: { [weak self] (urls) in
            guard let self = self else { return }
            uploadRequest.setFileUrls(urls)
            self.continueUploadAfterAssetsWrittenToDisk(uploadRequest: uploadRequest, progress: progress)
        })

        return progress
    }
    
    public func cancelUpload(uploadRequest: UploadRequest) {
        
        // cancel the operation
        for operation in uploadRequest.operationsArray {
            operation.cancel()
            operation.dataTask = nil
        }
        
        uploadRequestSession?.invalidateAndCancel()
        
        // todo i might need to wait until the system throws an error on this
        // find request and remove it
        notifyListenersStatusChanged(.cancelled, uploadRequest: uploadRequest)
        progresses.removeValue(forKey: uploadRequest.requestId)
        self.uploadRequests.removeAll(where: { $0.requestId == uploadRequest.requestId })
    }
    
    func continueUploadAfterAssetsWrittenToDisk(uploadRequest: UploadRequest, progress: ProgressGroup) {
        uploadedAlbumIds.removeAll()
        
        // create fileItems
        let collection = self.getFileCollection(uploadRequest: uploadRequest)
        
        // add kvo to update UI
        let progressObserver = progress.parentProgress.observe(\.fractionCompleted) { [weak self] (parentProgress, _) in
            guard let self = self else { return }
            
            for progressItem in self.progresses {
                if parentProgress == progressItem.value.parentProgress {
                    DispatchQueue.main.async {
                        self.notifyListenersDidReceiveProgress(progressItem.value, uploadRequest: self.getUploadRequestFor(id: progressItem.key))
                    }
                }
            }
        }
        
        self.progressObserver.append(progressObserver)
        
        for i in 0 ..< collection.items.count {
            let item = collection.items[i]
            progress.addChild(progress: item.progress)
            
            let operation = Request.MultiMediaUploadOperation(uploadRequest: uploadRequest, item: item)
            uploadRequest.operationsArray.append(operation)
            uploadRequest.queue.addOperation(operation)
        }
        
        // adding total in multiples of 100, it just needs to be initialized to something,
        // will be updated by system as children are added to the parent progress
       // progress.totalUnitCount = Int64(100 * collection.items.count)
    }
    
    public func markRequestStatusStaging(uploadRequest: UploadRequest) {
        notifyListenersStatusChanged(.staging, uploadRequest: uploadRequest)
    }
    
    /**
     *  get the file collection based off upload type
     *  @param fileURLs : files to upload
     *
     *  @return FileUploadItemCollection : collection of files to upload
     */
    private func getFileCollection(uploadRequest: UploadRequest) -> FileUploadItemCollection {
        switch uploadRequest.type {
        case .file:
            return FileUploadItemCollection(urls: uploadRequest.fileURLs, requestId: uploadRequest.requestId)
        case .album:
            return FileUploadItemCollection(urls: uploadRequest.fileURLs, isFromPost: uploadRequest.fromPost, requestId: uploadRequest.requestId)
        case .stream:
            return FileUploadItemCollection(urls: uploadRequest.fileURLs, requestId: uploadRequest.requestId)
        }
    }

    // MARK: URLSession delegates

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {

        // find the task in the array so we can update the item and
        for requests in uploadRequests {
            for operation in requests.operationsArray {
                guard let operationTask = operation.dataTask else {
                    // not the task data was received for
                    return
                }
                
                if operationTask.taskIdentifier == dataTask.taskIdentifier {
                    if let httpResponse = dataTask.response as? HTTPURLResponse {
                        if httpResponse.statusCode != 200 {
                            // see if we get some sort of rejection from backend
                            let resonse2 = Request.JSONResponse()
                            resonse2.responseData(response: httpResponse, data: data, error: nil)
                            
                            let errorMessage = extractErrorMessage(resonse2.json)
                            handleFailedItem(operation: operation, errorMessage: errorMessage)
                            handleFailedItemToLog(operation: operation, statusCode: httpResponse.statusCode, extraInfoString: resonse2.json.jsonString())
                        } else {
                            let response = Request.ArrayResponse()
                            response.responseArray(response: httpResponse, data: data, error: nil)
                            let resonse2 = Request.JSONResponse()
                            resonse2.responseData(response: httpResponse, data: data, error: nil)
                            uploadedAlbumIds.append(contentsOf: response.photoIDs)
                            
                            handleSuccessCleanup(operation: operation)
                        }
                        break
                        
                    } else {
                        handleFailedItem(operation: operation, errorMessage: nil)
                        handleFailedItemToLog(operation: operation, statusCode: 1, extraInfoString: "failure occured after no dataTask was present")
                    }
                }
            }
        }
    }
    
    // Extract error message from upload
    func extractErrorMessage(_ dict: [String: Any]) -> String {
        if let errors = dict["errors"] as? [String: Any] {
            if let scheduledStart = errors["scheduled_start"] as? [[String: Any]] {
                for item in scheduledStart {
                    if let message = item["message"] as? String {
                        return message
                    }
                }
            }
        }
        
        return ""
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {

        for requests in uploadRequests {
            for operation in requests.operationsArray {
                guard let operationTask = operation.dataTask else {
                    // not the task data was received for
                    return
                }
                
                // find the task in the array so we can update the item and
                if operationTask.taskIdentifier == task.taskIdentifier {
                    notifyListenersStatusChanged(.inProgress, uploadRequest: operation.uploadRequest)
                    operation.item.updateProgress(bytesSent: bytesSent, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
                    
                    notifyListenersBytesSent(uploadRequest: operation.uploadRequest, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        if error != nil {
            for requests in uploadRequests {
                // find the operation so we can complete it
                for operation in requests.operationsArray {
                    guard let operationTask = operation.dataTask else {
                        return
                    }
                    
                    if operationTask.taskIdentifier == task.taskIdentifier {
                        handleFailedItem(operation: operation, errorMessage: nil)

                        if let error = error {
                            handleFailedItemToLog(operation: operation, statusCode: 2, extraInfoString: error.localizedDescription)
                        } else {
                            handleFailedItemToLog(operation: operation, statusCode: 3, extraInfoString: "error occured in didCompleteWithError with nil error")
                        }
                    }
                }
            }
          //  Errors.reportError(message: "didCompleteWithError \(error?.localizedDescription ?? "")")
        }
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            if let completionHandler = self.backgroundSessionCompletionHander {
                self.backgroundSessionCompletionHander = nil
                completionHandler()
            }
        }
    }

    // IMPORTANT NOTE: this function is called every time a operation is completed.  The for loop and everything after is for monitoring when all operations have finished.
    private func handleSuccessCleanup(operation: Request.MultiMediaUploadOperation) {

        // set progress completed just in case didSendBody gets stuck at like 99 or something weird
        operation.item.setProgressCompleted()
        operation.completeOperation()

        // If the queue has hit 0 tasks, inform the client of completion and
        // clear the files from the albums directory
        for requests in uploadRequests {
            for operation in requests.operationsArray {
                if !operation.isFinished {
                    // operation exists that isn't finished
                    return
                }
            }
        }

        let completedRequest = getUploadRequestFor(id: operation.item.requestId)
        notifyListenersStatusChanged(.completed, uploadRequest: completedRequest)
        notifyListenersDidCompleteWithIds(uploadedAlbumIds, uploadRequest: completedRequest)
        
        // nil out the operation otherwise it is retained
        uploadRequestSession?.finishTasksAndInvalidate()
        operation.dataTask = nil
        
        // remove from Request library
        progresses.removeValue(forKey: completedRequest.requestId)
        self.uploadRequests.removeAll(where: { $0.requestId == completedRequest.requestId })
    }

    private func handleFailedItem(operation: Request.MultiMediaUploadOperation, errorMessage: String?) {
        // todo in the future we need to work with UX to find a more elegant way of handling failures
        // in the mean time, just silently failing and removing the operation
        operation.item.setItemProgressFailed()
        operation.completeOperation()
        let failedRequest = getUploadRequestFor(id: operation.item.requestId)
        notifyListenersStatusChanged(.failed, uploadRequest: failedRequest)
        
        for requests in uploadRequests {
            if let index = requests.operationsArray.firstIndex(of: operation) {
                requests.operationsArray.remove(at: index)
            }
        }
        notifyListenersDidReceiveUploadError(uploadRequest: failedRequest, errorMessage)
        
        // nil out the operation otherwise it is retained
        uploadRequestSession?.invalidateAndCancel()
        operation.dataTask = nil
        
        // remove from Request library
        progresses.removeValue(forKey: failedRequest.requestId)
        self.uploadRequests.removeAll(where: { $0.requestId == failedRequest.requestId })
    }
    
    private func handleFailedItemToLog(operation: Request.MultiMediaUploadOperation, statusCode: Int, extraInfoString: String) {
        let failedRequest = getUploadRequestFor(id: operation.item.requestId)
        let extraInfoError = NSError(domain: "com.drund.testing", code: 1, userInfo: [NSLocalizedDescriptionKey: extraInfoString])

        notifyListenersDidReceiveErrorToLog(uploadRequest: failedRequest, extraInfoError, statusCode: statusCode)
    }
    
    private func getUploadRequestFor(id: String) -> UploadRequest {
        for request in self.uploadRequests {
            if id == request.requestId {
                return request
            }
        }
        return UploadRequest()
    }
    
    // MARK: Delegate Functions
    
    func notifyListenersStatusChanged(_ status: UploadStatus, uploadRequest: UploadRequest) {
        
        // if not a background upload, we need to handle removing the old fileUrls
        // weird place to do this, it does need to move, but for now just making this work and making sure user doesn't end up with files on their phone forever
        if !uploadRequest.isBackgroundUpload && (status == .completed || status == .failed || status == .cancelled) {
            for url in uploadRequest.fileURLs {
                _ = FileManagerUtils.removeFileItem(at: url)
            }
        }
        
        for delegate in delegates {
            delegate.weakUploadRequestDelegate?.uploadRequestManagerUploadStatusChanged?(status, request: uploadRequest)
        }
    }
    
    func notifyListenersDidReceiveProgress(_ progress: ProgressGroup, uploadRequest: UploadRequest) {
        for delegate in delegates {
            delegate.weakUploadRequestDelegate?.uploadRequestManagerDidReceiveProgress(progress: progress, request: uploadRequest)
        }
    }
    
    func notifyListenersDidCompleteWithIds(_ ids: [Int], uploadRequest: UploadRequest) {
        for delegate in delegates {
            delegate.weakUploadRequestDelegate?.uploadRequestManagerDidCompleteWithIds(successIds: ids, request: uploadRequest)
        }
    }
    
    func notifyListenersDidSaveUploadData(_ fileDataURL: URL, uploadRequest: UploadRequest) {
        for delegate in delegates {
            delegate.weakUploadRequestDelegate?.uploadRequestManagerDidSaveUploadData?(fileUploadDataURL: fileDataURL, request: uploadRequest)
        }
    }
    
    func notifyListenersBytesSent(uploadRequest: UploadRequest, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        for delegate in delegates {
            delegate.weakUploadRequestDelegate?.uploadRequestManagerUpdateBytesSent?(request: uploadRequest, totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
        }
    }
    
    func notifyListenersDidReceiveUploadError(uploadRequest: UploadRequest, _ errorMessage: String?) {
        for delegate in delegates {
            delegate.weakUploadRequestDelegate?.uploadRequestManagerDidReceiveError?(request: uploadRequest, errorMessage: errorMessage)
        }
    }
    
    func notifyListenersDidReceiveErrorToLog(uploadRequest: UploadRequest, _ error: Error, statusCode: Int) {
        for delegate in delegates {
            delegate.weakUploadRequestDelegate?.uploadRequestManagerLogErrorMessage?(request: uploadRequest, error, statusCode: statusCode)
        }
    }
 }
