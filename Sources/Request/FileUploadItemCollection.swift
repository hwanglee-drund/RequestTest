//
//  FileUploadItemCollection.swift
//  Drund
//
//  Created by Mike Donahue on 7/13/18.
//  Copyright © 2018 Drund. All rights reserved.
//

import Foundation

class FileUploadItemCollection {
    let items: [FileUploadItem]
    
    init(urls: [URL], isFromPost: Bool = false, requestId: String) {
        self.items = urls.map { (urls: URL) -> FileUploadItem in
            return FileUploadItem(fileURL: urls, isFromPost: isFromPost, requestId: requestId)
        }
    }
}
