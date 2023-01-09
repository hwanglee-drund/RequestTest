//
//  UploadRequest.swift
//  Drund
//
//  Created by Shawna MacNabb on 3/5/19.
//  Copyright © 2019 Drund. All rights reserved.
//

import UIKit
import Photos

public enum UploadType {
    case file
    case album
    case stream
}

open class UploadRequest: NSObject {
    
    // common amongst album and drive
    var endpoint: String = ""
    var type: UploadType = .album
    
    // album specific
    var fromPost: Bool = false
    
    // drive specific
    var toFolderID: Int? = 0
    
    // file URL
    public private(set) var fileURLs: [URL] = []
    
    // current community id
    // TODO POST REFACTOR THIS NEEDS TO CHANGE
    var currentCommunityId: Int = 0
    
    /// Initialize and upload operation queue
    let queue = Request.UploadOperationQueue()
    
    /// assets to upload
    public var assets: [PHAsset] = [PHAsset]()
    
    public var requestId: String = UUID().uuidString
    
    var operationsArray: Array = [Request.MultiMediaUploadOperation]()
    
    var extraParameters: [String: Any]?
    
    /// denotes if the upload should be performed in the background or not
    public private(set) var isBackgroundUpload: Bool = false
    
    override public init() {}
    
    // used to generate a new request id if we are rescheduling the upload, it needs to be an unique id
    public func regenerateRequestId() {
        requestId = UUID().uuidString
    }
    
    public init(requestId: String, uploadType: UploadType, currentCommunityId: Int) {
        self.type = uploadType
        self.currentCommunityId = currentCommunityId
        self.requestId = requestId
        
        if uploadType == .stream {
            self.isBackgroundUpload = true
        }
        
        queue.maxConcurrentOperationCount = 3
    }
    
    /**
     *  Upload request for Album
     *  @param:
     */
    public init(fileURLs: [URL], uploadType: UploadType, fromPost: Bool, endpoint: String, currentCommunityId: Int) {
        super.init()
        
        self.fileURLs = fileURLs
        self.type = uploadType
        self.fromPost = fromPost
        self.endpoint = endpoint
        self.currentCommunityId = currentCommunityId
        
        if uploadType == .stream {
            self.isBackgroundUpload = true
        }
        
        queue.maxConcurrentOperationCount = 3
    }
    
    public init(assets: [PHAsset], uploadType: UploadType, fromPost: Bool, endpoint: String, currentCommunityId: Int) {
        super.init()
        
        self.assets = assets
        self.type = uploadType
        self.fromPost = fromPost
        self.endpoint = endpoint
        self.currentCommunityId = currentCommunityId
        
        if uploadType == .stream {
            self.isBackgroundUpload = true
        }
        
        queue.maxConcurrentOperationCount = 3
    }
    
    /**
     *  Upload request for Drive
     *  @param:
     */
    public init(fileURLs: [URL], uploadType: UploadType, toFolderID: Int?, endpoint: String, currentCommunityId: Int) {
        super.init()
        
        self.fileURLs = fileURLs
        self.type = uploadType
        self.toFolderID = toFolderID
        self.endpoint = endpoint
        self.currentCommunityId = currentCommunityId
        
        if uploadType == .stream {
            self.isBackgroundUpload = true
        }
        
        queue.maxConcurrentOperationCount = 3
    }
    
    public init(assets: [PHAsset], uploadType: UploadType, toFolderID: Int?, endpoint: String, currentCommunityId: Int) {
        super.init()
        
        self.assets = assets
        self.type = uploadType
        self.toFolderID = toFolderID
        self.endpoint = endpoint
        self.currentCommunityId = currentCommunityId
        if uploadType == .stream {
            self.isBackgroundUpload = true
        }
        
        queue.maxConcurrentOperationCount = 3
    }
    
    public init(assets: [PHAsset], uploadType: UploadType, endpoint: String, currentCommunityId: Int) {
        self.assets = assets
        self.type = uploadType
        self.endpoint = endpoint
        self.currentCommunityId = currentCommunityId
        
        if uploadType == .stream {
            self.isBackgroundUpload = true
        }
        
        queue.maxConcurrentOperationCount = 3
    }
    
    public init(fileURLs: [URL], uploadType: UploadType, endpoint: String, currentCommunityId: Int) {
        self.type = uploadType
        self.endpoint = endpoint
        self.currentCommunityId = currentCommunityId
        self.fileURLs = fileURLs
        
        if uploadType == .stream {
            self.isBackgroundUpload = true
        }
        
        queue.maxConcurrentOperationCount = 1
    }
    
    public func addExtraParametersToUpload(_ params: [String: Any]) {
        self.extraParameters = params
    }
    
    // set the file URLs after the assets were moved
    public func setFileUrls(_ urls: [URL]) {
        self.fileURLs = urls
    }
    
    public func resetEndpoint(_ endpoint: String) {
        self.endpoint = endpoint
    }
    
    public func cancelAllOperations() {
        queue.cancelAllOperations()
    }
}
