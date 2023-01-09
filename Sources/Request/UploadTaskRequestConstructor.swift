//
//  UploadTaskRequestConstructor.swift
//  Request
//
//  Created by Shawna MacNabb on 9/18/20.
//  Copyright © 2020 Shawna MacNabb. All rights reserved.
//

import UIKit
import Foundation

class UploadTaskRequestConstructor {

    // Creates a standard URLRequest object with the multipart data (including images or video) appended to the body
    static func createStandardRequest(styledEndpoint: String, fileURL: URL, fileKey: String, extraFormData: [String: Any]?, defaultHeaders: [String: String]) -> URLRequest? {
        
        var uploadRequest: URLRequest?
        guard let styledURL = URL(string: styledEndpoint) else { return uploadRequest }
        
        let bounaryID = UUID().uuidString
        
        uploadRequest = URLRequest(url: styledURL)
        uploadRequest?.allHTTPHeaderFields = defaultHeaders
        uploadRequest?.addValue("multipart/form-data; boundary=\(bounaryID)", forHTTPHeaderField: "Content-Type")
        uploadRequest?.httpMethod = "POST"
        
        let fileName = fileURL.lastPathComponent
        let mimeType = MimeType(url: fileURL)
        
        let mutableData = NSMutableData()
        guard let firstBoundary = "--\(bounaryID)\r\n".data(using: .utf8) else { return uploadRequest }
        
        if let formData = extraFormData {
            for (key, value) in formData {
                guard let keyData = "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8) else { break }
                guard let valueData = "\(value)\r\n".data(using: .utf8) else { break }
                guard let boundarySpace = "--\(bounaryID)\r\n".data(using: .utf8) else { break }
                mutableData.append(keyData)
                mutableData.append(valueData)
                mutableData.append(boundarySpace)
            }
        }
        
        guard let fileNameData = "Content-Disposition: form-data; name=\"\(fileKey)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8) else { return uploadRequest }
        guard let contenttype = "Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8) else { return uploadRequest }
        guard let boundary = "--\(bounaryID)--\r\n".data(using: .utf8) else { return uploadRequest }
        
        mutableData.append(firstBoundary)
        mutableData.append(fileNameData)
        mutableData.append(contenttype)
        
        let inputStream = InputStream(url: fileURL)
        
        guard let input = inputStream else { return uploadRequest }
        input.open()
        
        let mutableImageData = NSMutableData()
        
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        
        while input.hasBytesAvailable {
            
            let read = input.read(buffer, maxLength: bufferSize)
            mutableImageData.append(buffer, length: read)
        }
        
        buffer.deallocate()
        input.close()
        
        mutableData.append(mutableImageData as Data)
        
        guard let some = "\r\n".data(using: .utf8) else { return uploadRequest }
        mutableData.append(some)
        mutableData.append(boundary)
        
        uploadRequest?.httpBody = mutableData as Data
        
        return uploadRequest
    }
    
    // creates a request with multipart data not added to the body of the URLRequest.
    // Background uploads do not support this, so the data is later saved to disk.
    static func createRequestForBackgroundUpload(styledEndpoint: String, defaultHeaders: [String: String]) -> (request: URLRequest?, boundaryId: String) {
        var uploadRequest: URLRequest?
        let bounaryID = UUID().uuidString
        
        guard let styledURL = URL(string: styledEndpoint) else { return (uploadRequest, bounaryID) }
        
        uploadRequest = URLRequest(url: styledURL)
        uploadRequest?.allHTTPHeaderFields = defaultHeaders
        uploadRequest?.addValue("multipart/form-data; boundary=\(bounaryID)", forHTTPHeaderField: "Content-Type")
        uploadRequest?.httpMethod = "POST"
        
        return (uploadRequest, bounaryID)
    }
    
    static func writeMultipartDataToDisk(fileURL: URL, fileKey: String, extraFormData: [String: Any]?, boundaryId: String) -> URL? {
        
        let fileName = fileURL.lastPathComponent
        let mimeType = MimeType(url: fileURL)
        
        let mutableData = NSMutableData()
        guard let firstBoundary = "--\(boundaryId)\r\n".data(using: .utf8) else { return nil }
        
        if let formData = extraFormData {
            for (key, value) in formData {
                guard let keyData = "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8) else { break }
                guard let valueData = "\(value)\r\n".data(using: .utf8) else { break }
                guard let boundarySpace = "--\(boundaryId)\r\n".data(using: .utf8) else { break }
                mutableData.append(keyData)
                mutableData.append(valueData)
                mutableData.append(boundarySpace)
            }
        }
        
        guard let fileNameData = "Content-Disposition: form-data; name=\"\(fileKey)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8) else { return nil }
        guard let contenttype = "Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8) else { return nil }
        guard let boundary = "--\(boundaryId)--\r\n".data(using: .utf8) else { return nil }
        
        mutableData.append(firstBoundary)
        mutableData.append(fileNameData)
        mutableData.append(contenttype)
        
        // write this chunk to the file, standard write since nothing has been added to file yet
        guard let finalFileName = FileManagerUtils.writeDataTextFile(data: mutableData as Data, fileName: fileName) else { return nil }
        
        // write the photo/video to disk
        _ = FileManagerUtils.writeLargeData(outputFilname: finalFileName.lastPathComponent, inputURL: fileURL)
        
        let lastPieceofData = NSMutableData()
        guard let some = "\r\n".data(using: .utf8) else { return nil }
        lastPieceofData.append(some)
        lastPieceofData.append(boundary)
        
        FileManagerUtils.appendDataToFile(fileURL: finalFileName, data: lastPieceofData as Data)
        
        return finalFileName
    }
}
