//
//  UploadPlayerOperationgQueue.swift
//  Request
//
//  Created by Dan Turner on 11/28/22.
//  Copyright © 2022 Drund. All rights reserved.
//

import Foundation

public class UploadPlayerOperationQueue: OperationQueue {
   override public func cancelAllOperations() {
      for case let operation as MockPhotoUploadOperation in operations {
         operation.cancel()
      }

      super.cancelAllOperations()
   }
}

//public class PhotoUploadOperation: AsyncOperation {
//
//   // define properties to hold everything that you'll supply when you instantiate
//   // this object and will be used when the request finally starts
//   //
//   // in this example, I'll keep track of (a) URL; and (b) closure to call when request is done
//
//    let endpoint: String
//   let item: FileUploadItem
//   var extraFormData = [String: Any]()
//
//   fileprivate var formData: [String: Any] = [:]
//
//   // we'll also keep track of the resulting request operation in case we need to cancel it later
//
//   var dataTask: URLSessionDataTask?
//
//   let uploadRequest: UploadRequest
//
//   // define init method that captures all of the properties to be used when issuing the request
//
//    init(uploadRequest: UploadRequest, item: FileUploadItem, tournamentID: Int, teamID: Int, playerID: Int) {
//      self.uploadRequest = uploadRequest
//      self.extraFormData = uploadRequest.extraParameters ?? [String: Any]()
//
//      //  LogInfo("[Request] album upload endPoint: \(uploadRequest.endpoint)")
//
//      if let idData = "\(uploadRequest.currentCommunityId)".data(using: .utf8) {
//         formData["community_id"] = idData
//      }
//      self.item = item
//
//      super.init()
//
//      switch uploadRequest.type {
//      case .file:
//         if let key = uploadRequest.toFolderID {
//            extraFormData["folder_key"] = key
//         }
//         break
//      case .album:
//         if item.isFromPost {
//            extraFormData["is_upload_only"] = "on"
//         }
//         break
//      default:
//         break
//      }
//
//        endpoint = uploadRequest.endpoint
//   }
//
//   // when the operation actually starts, this is the method that will be called
//   /**
//    *  NOTE: progress needs to be marked failed/succeeded and then completion handler can be called.  CompleteOperation should be the LAST thing called
//    */
//   override public func main() {
//       let request = UploadTaskRequestConstructor.createRequestForBackgroundUpload(styledEndpoint: endpoint, defaultHeaders: defaultHeaders)
//       if let returnedRequest = request.request, let session = UploadRequestManager.shared.uploadRequestSession {
//          // save the data to disk so we can point the uploadTask to the file data to upload
//          if let savedDataLocation = UploadTaskRequestConstructor.writeMultipartDataToDisk(fileURL: item.fileURL, fileKey: fileKey, extraFormData: extraFormData, boundaryId: request.boundaryId) {
//             dataTask = session.uploadTask(with: returnedRequest, fromFile: savedDataLocation)
//             UploadRequestManager.shared.notifyListenersDidSaveUploadData(savedDataLocation, uploadRequest: uploadRequest)
//             UploadRequestManager.shared.notifyListenersStatusChanged(.staged, uploadRequest: uploadRequest)
//             dataTask?.resume()
//          }
//       } else {
//          // todo something went wrong that should never happen since we have complete control over the request params
//          item.setItemProgressFailed()
//       }
//   }
//
//   // we'll also support canceling the request, in case we need it
//
//   override public func cancel() {
//      //    LogInfo("[Request] task cancelled")
//      dataTask?.cancel()
//
//      super.cancel()
//   }
//}

public class MockPhotoUploadOperation: AsyncOperation, ObservableObject {
    var timer: Timer? = .none

    @Published public var progress: Double = 0

    public override func main() {
        if timer == .none {
            DispatchQueue.main.async { [weak self] in
                guard let `self` = self else { return }

                self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    switch self.progress {
                    case 1...:
                        self.stopTimer()
                        self.completeOperation()

                    default:
                        self.progress += 0.05
                    }
                }
            }
        }
    }

    func stopTimer() {
        if let timer = timer {
            timer.invalidate()
            self.timer = .none
        }
    }

    override public func cancel() {
        stopTimer()

        super.cancel()
    }
}
