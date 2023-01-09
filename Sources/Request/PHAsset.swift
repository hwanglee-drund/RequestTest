//
//  PHAsset.swift
//  Drund
//
//  Created by Mike Donahue on 7/14/17.
//  Copyright © 2017 Drund. All rights reserved.
//

import Photos
import UIKit

extension PHAsset {
    public struct VideoMetadata {
        public internal(set) var name: String?
        public internal(set) var fileSize: Int64?
        public internal(set) var duration: Int?
        public internal(set) var thumbnail: UIImage?
        
        init() {
            
        }
        
        public var fileSizePretty: String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useAll]
            formatter.countStyle = .file
            if let fileSize = self.fileSize {
                return formatter.string(fromByteCount: Int64(fileSize))
            } else {
                return formatter.string(fromByteCount: 0)
            }
        }
    }
    
    /**
     * Gets the file's thumbnail for the `PHAsset`.
     * - Parameter completionHandler: Completion block for the media edit request. It will return the `UIImage` in that block
     */
    public func getThumbnail(size: CGSize, completionHandler: @escaping ((_ image: UIImage?) -> Void)) {
        let options = PHImageRequestOptions()
        
        options.resizeMode = .none
        
        PHImageManager.default().requestImage(for: self, targetSize: size, contentMode: .aspectFill, options: options) { (image: UIImage?, _: [AnyHashable: Any]?) in
            if let thumbImage = image {
                // swiftlint:disable all
                completionHandler(UIImage(cgImage: thumbImage.cgImage!, scale: UIScreen.main.scale, orientation: thumbImage.imageOrientation))
                // swiftlint:enable all
            }
            
            completionHandler(nil)
        }
    }
    
    /**
     * Gets the video file's metadata for the  given`PHAsset`.
     * - Parameter completionHandler: Completion block for the media edit request. It will return the `VideoMetadata` in that block
     */
    public func getVideoMetadata(_ thumbnailSize: CGSize = CGSize(width: 128, height: 128), completion: @escaping ((_ metadata: VideoMetadata?) -> Void)) {
        let options = PHVideoRequestOptions()
        
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        var metadata = VideoMetadata()
        let resources = PHAssetResource.assetResources(for: self)
        
        metadata.duration = Int(self.duration)
        
        // if edited video we need to grab the filename and size from the actual video, otherwise the first item in the PHAssetResource is
        if let editedVideo = resources.first(where: { $0.type == .fullSizeVideo }) {
            metadata.name = editedVideo.originalFilename
            metadata.fileSize = editedVideo.value(forKey: "fileSize") as? Int64 ?? 0
        } else {
            metadata.name = resources.first?.originalFilename ?? ""
            metadata.fileSize = resources.first?.value(forKey: "fileSize") as? Int64 ?? 0
        }
                
        let manager = PHImageManager.default()
        let option = PHImageRequestOptions()
        
        option.isSynchronous = true
        
        let pointSize = CGSize(width: thumbnailSize.width * UIScreen.main.scale, height: thumbnailSize.height * UIScreen.main.scale)
        
        DispatchQueue.global().async {
            manager.requestImage(for: self, targetSize: pointSize, contentMode: .aspectFill, options: option, resultHandler: {(result, _) -> Void in
                metadata.thumbnail = result
                DispatchQueue.main.async {
                    completion(metadata)
                }
            })
        }
    }
    
    /**
     * Gets the file's image for the `PHAsset`.
     * - Parameter completionHandler: Completion block for the media edit request. It will return the `UIImage` in that block
     */
    public func getImage(completionHandler: @escaping ((_ image: UIImage?) -> Void)) {
        let options = PHImageRequestOptions()
        
        options.resizeMode = .none
        options.isSynchronous = true
                
        PHImageManager.default().requestImage(for: self, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFill, options: options) { (image: UIImage?, _: [AnyHashable: Any]?) in
            if let thumbImage = image {
                // swiftlint:disable all
                completionHandler(UIImage(cgImage: thumbImage.cgImage!, scale: UIScreen.main.scale, orientation: thumbImage.imageOrientation))
                // swiftlint:enable all
            }
            
            completionHandler(nil)
        }
    }
    
    /**
     * Attempts to write the asset to our temporary directory (See FileUtils) and return the new
     * file URL in the completion block.
     * - Parameter completion: Completion block for the write attempt. Will have a URL if the write
     * was successful.
     */
    public func writeToTempDirectory(isStreamUpload: Bool, completion: @escaping ((_ tempURL: URL?) -> Void)) {

        guard let documentsDirectory = FileManagerUtils.getDrundUserAlbumUploadsDirectory() else {
            completion(nil)
            return
        }
        
        let imageManager = PHImageManager.default()
                
        switch self.mediaType {
        case .image:
            // Set image request options
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.isSynchronous = true
            
            // Request the image data
            imageManager.requestImage(for: self, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFill, options: options) { (uiImage: UIImage?, _: [AnyHashable: Any]?) in

                // Make sure the image exists
                guard let image = uiImage else {
                    completion(nil)
                    return
                }
                
                // Append a newly generated name to the file path
                let imagePath = documentsDirectory.appendingPathComponent("\(UUID().uuidString).jpeg")
                
                // Encode this image into PNG
                if let data = image.toJPEGDataWithCompression(compressionRatio: 0.8) {
                    do {
                        // Try to write the image data our to our new file path
                        try data.write(to: imagePath, options: [])
                        DispatchQueue.main.async {
                            // Complete with the new image path
                            completion(imagePath)
                        }
                    } catch let error {
                        print("Error: \(error.localizedDescription)")
                        // Error writing file, report error
                   //     Errors.reportError(message: "Error writing album upload file to temp directory.", extras: ["error": error.localizedDescription, "PHAsset.mediaType": "\(self.mediaType.rawValue)", "PHAsset.sourceType": "\(self.sourceType.rawValue)"])
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                    }
                }
            }
        case .video:
            // Set video request options
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
        
            // Request the AVAsset and prepare for export
            imageManager.requestAVAsset(forVideo: self, options: options) { (avAsset, _, _) in
                guard let asset = avAsset as? AVURLAsset else {
                    completion(nil)
                    return
                }
                
                // Initalize exporter with asset
                guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                    completion(nil)
                    return
                }
                                                
                // Append a newly generated name to the file path
                let resources = PHAssetResource.assetResources(for: self)
                // if edited video we need to grab the filename of the video, otherwise the first item in the PHAssetResource is
                var fileName: String = ""
                if let editedVideo = resources.first(where: { $0.type == .fullSizeVideo }) {
                   fileName = editedVideo.originalFilename
                } else {
                    fileName = resources.first?.originalFilename ?? "\(UUID().uuidString).mp4"
                }
                
                let videoPath = documentsDirectory.appendingPathComponent("\(fileName)")
                
                exporter.outputURL = videoPath
                exporter.outputFileType = AVFileType.mp4
                
                let fileURL = FileManagerUtils.writeLargeData(outputFilname: fileName, inputURL: asset.url)
                completion(fileURL)
            }
        default:
            break
        }
    }
    
    public class OutputOperation: AsyncOperation {
        public private(set) var asset: PHAsset
        
        private var completion: (_ fileURL: URL?) -> Void
        private var isStreamUpload: Bool
        
        public init(asset: PHAsset, isStreamUpload: Bool, completion: @escaping (_ fileURL: URL?) -> Void) {
            self.completion = completion
            self.asset = asset
            self.isStreamUpload = isStreamUpload
            super.init()
            self.qualityOfService = .userInitiated
        }
        
        override public func main() {
            DispatchQueue.global().async { [weak self] in
                guard let self = self, self.isCancelled == false else { return }
                
                self.asset.writeToTempDirectory(isStreamUpload: self.isStreamUpload, completion: { (fileURL) in
                    self.completeOperation()
                    self.completion(fileURL)
                })
            }
        }
    }
}
