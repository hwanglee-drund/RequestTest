//
//  FileUploadItem.swift
//  Drund
//
//  Created by Mike Donahue on 7/13/18.
//  Copyright © 2018 Drund. All rights reserved.
//

import Foundation

/**
 * Class to hold information about a single file upload task.
 */
class FileUploadItem {
    /// Progress of the current task
    var progress: DProgress = DProgress()
    
    /// File URL for upload
    var fileURL: URL
    
    /// If this task orginated from post create. For example, album attachments on a post
    var isFromPost: Bool = false
    
    /// reference of the totalBytesExpectedToSend from the URLSessionTask
    var totalBytesExpectedToSend: Int64 = 0
    
    /// the requestId the item is apart of
    var requestId: String
    
    init(fileURL: URL, isFromPost: Bool = false, requestId: String) {
        self.fileURL = fileURL
        self.isFromPost = isFromPost
        self.requestId = requestId
        
        // needs to be initalized to something so we can just give it to the UI element with a value
        self.progress.totalUnitCount = 100
    }
    
    func updateProgress(bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        
        // update the progress from the delegate
        self.progress.totalUnitCount = totalBytesExpectedToSend
        self.progress.completedUnitCount = totalBytesSent
                
        // keep track of values so we can mark complete just in case totalBytesSent and Expected never match
        self.totalBytesExpectedToSend = totalBytesExpectedToSend
    }
    
    func setProgressCompleted() {
        // just in case totalBytesSent and totalBytesExpectedToSend don't match
        // the progress will never be marked complete.  Pretty rare thing to happen, but it can happen
        self.progress.totalUnitCount = totalBytesExpectedToSend
        self.progress.completedUnitCount = totalBytesExpectedToSend
    }
    
    func setItemProgressFailed() {
        // todo in the future we need to do something more here with an image that failed to uplaod then just mark it completed but
        // it takes some UI/UX thought
        // for now marking completed
        self.progress.totalUnitCount = totalBytesExpectedToSend
        self.progress.completedUnitCount = totalBytesExpectedToSend
    }
}
