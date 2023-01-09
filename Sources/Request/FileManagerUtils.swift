//
//  FileManagerUtils.swift
//  Drund
//
//  Created by Mike Donahue on 3/11/19.
//  Copyright © 2019 Drund. All rights reserved.
//

import Foundation
import Photos

public struct FileManagerUtils {
    private static let userAlbumUploadsDirectory = "drundalbumuploads"
    private static let userStreamUploadsDirectory = "drundStreamUpload"
    
    private static var operationQueue: OperationQueue?
    
    public static var documentsDirectory: URL? {
        guard let docDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docDirectory
    }
    
    public static func writeAssetToDisk(_ asset: PHAsset, completion: @escaping (_ filesURL: URL) -> Void) {
        
        // Initialize the operation queue for writing out assets to disk
        let outputOperationQueue = OperationQueue()
        outputOperationQueue.maxConcurrentOperationCount = 1
        self.operationQueue = outputOperationQueue
        
        // Function run each time a file is written out to disk.
        // After all operations are complete, it will trigger upload.
        let outputCompletion: (_ fileURL: URL?) -> Void = { url in
            // Check if the operation queue has hit it's end, if so
            // we can initate the upload
            if let fileURL = url, outputOperationQueue.operationCount == 0 {
                completion(fileURL)
            }
        }
        
        // Add all operations the the output operation queue
        outputOperationQueue.addOperation(PHAsset.OutputOperation(asset: asset, isStreamUpload: false, completion: outputCompletion))
    }
    
    public static func cancelCurrentOperations() {
        if let operationQueue = self.operationQueue {
            operationQueue.cancelAllOperations()
        }
    }
    
    public static func writeAssetsToDisk(_ assets: [PHAsset], completion: @escaping (_ filesURL: [URL]) -> Void) {
        
        // Initialize the operation queue for writing out assets to disk
        let outputOperationQueue = OperationQueue()
        outputOperationQueue.maxConcurrentOperationCount = 1
        var operations: [PHAsset.OutputOperation] = []
        
        var fileURLs: [URL] = []
        
        // Function run each time a file is written out to disk.
        // After all operations are complete, it will trigger upload.
        let outputCompletion: (_ fileURL: URL?) -> Void = { url in
            // Append the file url if it exists so we can upload it
            if let fileURL = url {
                fileURLs.append(fileURL)
            }
            
            // Check if the operation queue has hit it's end, if so
            // we can initate the upload
            if outputOperationQueue.operationCount == 0 {
                completion(fileURLs)
            }
        }
        
        // Create and append a list of async operations
        for i in 0 ..< assets.count {
            operations.append(PHAsset.OutputOperation(asset: assets[i], isStreamUpload: false, completion: outputCompletion))
        }
        
        // Add all operations the the output operation queue
        outputOperationQueue.addOperations(operations, waitUntilFinished: false)
    }
    
    public static func writeDataTextFile(data: Data, fileName: String) -> URL? {
        // tack on file extension to filename
        let fileName = fileName + ".txt"
        return self.write(data: data, fileName: fileName)
    }
    
    public static func writeData(data: Data, fileName: String) -> URL? {
        return self.write(data: data, fileName: fileName)
    }
    
    static func write(data: Data, fileName: String) -> URL? {
        
        guard var documentsDirectory = FileManagerUtils.documentsDirectory else { return nil }
        
        // Append our directory
        documentsDirectory = documentsDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: documentsDirectory)
            return documentsDirectory
        } catch let error {
            print("Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    static func writeLargeData(outputFilname: String, inputURL: URL) -> URL? {
        guard var documentsDirectory = FileManagerUtils.documentsDirectory else { return nil }

        // Append our filename
        documentsDirectory = documentsDirectory.appendingPathComponent(outputFilname)
        
        let inputStream = InputStream(url: inputURL)
        let outputStream = OutputStream(url: documentsDirectory, append: true)
        
        guard let input = inputStream else { return nil }
        guard let output = outputStream else { return nil }
        input.open()
        output.open()
        
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        
        while input.hasBytesAvailable {
            
            let read = input.read(buffer, maxLength: bufferSize)
            output.write(buffer, maxLength: read)
        }
        
        buffer.deallocate()
        input.close()
        output.close()
        
        return documentsDirectory
    }
    
    static func appendDataToFile(fileURL: URL, data: Data) {
        do {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        } catch {
            print("Can't open fileHandle \(error)")
        }
    }
    
    /**
     * Returns the URL we use to temporarily hold user uploads in the app.
     */
    public static func getDrundUserAlbumUploadsDirectory() -> URL? {
        // Get the base user documents URL
        guard var documentsDirectory = FileManagerUtils.documentsDirectory else { return nil }
        
        // Append our directory
        documentsDirectory = documentsDirectory.appendingPathComponent(userAlbumUploadsDirectory)
        
        // Init a file manager and check if the directory already exists, if not create it.
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: documentsDirectory.absoluteString, isDirectory: nil) {
            return documentsDirectory
        } else {
            do {
                try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
                return documentsDirectory
            } catch let error {
                print("Error: \(error.localizedDescription)")
                // Errors.reportError(message: "Error creating directory for temp album uploads. FileUtils.getDrundUserAlbumUploadsDirectory", extras: ["error": error.localizedDescription])
                return nil
            }
        }
    }
    
    /**
     * Returns the URL we use to temporarily hold stream uploads in the app.
     */
    public static func getDrundUserStreamUploadsDirectory() -> URL? {
        // Get the base user documents URL
        guard var documentsDirectory = FileManagerUtils.documentsDirectory else { return nil }
        
        // Append our directory
        documentsDirectory = documentsDirectory.appendingPathComponent(userStreamUploadsDirectory)
        
        // Init a file manager and check if the directory already exists, if not create it.
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: documentsDirectory.absoluteString, isDirectory: nil) {
            return documentsDirectory
        } else {
            do {
                try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
                return documentsDirectory
            } catch let error {
                print("Error: \(error.localizedDescription)")
                // Errors.reportError(message: "Error creating directory for temp album uploads. FileUtils.getDrundUserAlbumUploadsDirectory", extras: ["error": error.localizedDescription])
                return nil
            }
        }
    }
    
    /*
     *  Create the drund documents subfolder to hold files.
     *  The file is only created if it does not exist
     */
    public static func setupDocumentsDirectory() {
        
        guard let documentsDirectory = FileManagerUtils.documentsDirectory else { return }

        let dataPath = documentsDirectory.appendingPathComponent("drund")
        
        if !FileManager().fileExists(atPath: dataPath.path) {
            do {
                try FileManager.default.createDirectory(atPath: dataPath.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("couldn't create document directory")
            }
        }
    }
    
    public static func localDocumentsFilePath() -> URL? {
        
        return FileManagerUtils.documentsDirectory
    }
    
    /*
     *  Copy file from one location to another defined location
     *
     *  @parameter at: URL of the current location where the file is located
     *  @parameter to: URL of the destination of local file
     *
     *  @return Bool: Indication of whether the coping of the file has succeeded
     */
    public static func copyFileItem(at: URL, to: URL) -> NSError? {
        
        do {
            try FileManager.default.copyItem(at: at, to: to)
            return nil
        } catch (let writeError as NSError) {
            
            return writeError
        }
    }
    
    /*
     *  Moves file from one location to another
     *
     *  @discussion : Attempt to copy file from one location to another.  If the copy fails for the reason of file already existing, remove the file at the destination url and then attempt to copy file again.
     *
     *  @parameter at: Where the file is currently located
     *  @parameter to: Where the file is to be moved
     *
     *  @return Bool: Indication if the file was moved
     */
    public static func moveFileItem(at: URL, to: URL) -> Bool {
        
        // docs say to try and copy file and then see what the error is rather then call fileExists because race conditions occur when heavily using them.
        if let writeError = copyFileItem(at: at, to: to) {
            // TODO FIND THE CONST FOR THIS ERROR
            // File already exists, so remove if first
            if writeError.code == 516 {
                let isFileRemoved = FileManagerUtils.removeFileItem(at: to)
                if isFileRemoved {
                    // copy again
                    if let error = FileManagerUtils.copyFileItem(at: at, to: to) {
                        print("Error: \(error.localizedDescription)")
                        //   Errors.reportError(message: "something went wrong copying file again: \(error.code) description: \(error.localizedDescription)")
                        return false
                    } else {
                        return true
                    }
                } else {
                    // something went wrong again, have the user try again
                    //    LogError("[Request] download something weng wrong while removing local file")
                    return false
                }
            } else {
                // something else happened, can't really recover
                //  Errors.reportError(message: "something went wrong while moving file code: \(writeError.code) description: \(writeError.localizedDescription)")
                //   LogError("[Request] download errorCode: \(writeError.code) description: \(writeError.localizedDescription)")
                return false
            }
        } else {
            // succeeded
            return true
        }
    }
    
    /*
     *  Remove local file
     *
     *  @parameter at: URL of the current location where the file is located
     *
     *  @return Bool: Indication of whether the removing of the file has succeeded
     */
    public static func removeFileItem(at: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: at)
            return true
        } catch (let removeError) {
            print("Error: \(removeError.localizedDescription)")
            //  Errors.reportError(message: "Something went wrong while removing a file \(removeError)")
            return false
        }
    }
    
    public static func clearDocumentsDirectory(includeFolders: Bool = false) {
        guard let documentsDirectory = FileManagerUtils.documentsDirectory else { return }
        FileManagerUtils.recursivelyDeleteFilesStartingAtURL(documentsDirectory, usingFileManager: FileManager.default, includingFolders: true)
    }
    
    public static func clearDrundUserAlbumUploadsDirectory() {
        guard let documentsDirectory = FileManagerUtils.getDrundUserAlbumUploadsDirectory() else {
            return
        }
        
        FileManagerUtils.recursivelyDeleteFilesStartingAtURL(documentsDirectory, usingFileManager: FileManager.default, includingFolders: false)
    }
    
    private static func recursivelyDeleteFilesStartingAtURL(_ url: URL, usingFileManager fileManager: FileManager, includingFolders: Bool) {
        if let directoryContents = try? fileManager.contentsOfDirectory(atPath: url.path)  {
            var isFolder: ObjCBool = false
            for content in directoryContents {
                let contentURL = url.appendingPathComponent(content)
                
                if fileManager.fileExists(atPath: contentURL.path, isDirectory: &isFolder) {
                    if isFolder.boolValue {
                        FileManagerUtils.recursivelyDeleteFilesStartingAtURL(contentURL, usingFileManager: fileManager, includingFolders: includingFolders)
                        if includingFolders {
                            try? fileManager.removeItem(atPath: contentURL.path)
                        }
                    } else {
                        try? fileManager.removeItem(atPath: contentURL.path)
                    }
                }
            }
        }
    }
    
    /**
     * Attempts to delete a file at a given URL
     */
    static func deleteFileAtURL(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return
        }
    }
    
    /*
     *  Move a file from local location to the temporary directory
     *
     *  @parameter at: URL where the file is currently located
     *
     *  @return URL?: Location of where the move was moved to.  It is possible for this to fail in which case nil will be returned.
     */
    public static func moveFileToTempDirectory(_ at: URL) -> URL? {
        
        let filename = at.lastPathComponent
        
        let localURL = FileManager.default.temporaryDirectory
        let fullURL = localURL.appendingPathComponent(filename, isDirectory: false)
        
        let isFileMoved = FileManagerUtils.moveFileItem(at: at, to: fullURL)
        if isFileMoved {
            return fullURL
        } else {
            return nil
        }
    }
}
