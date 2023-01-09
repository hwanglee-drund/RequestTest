//
//  UIImage.swift
//  Request
//
//  Created by Shawna MacNabb on 7/9/20.
//  Copyright © 2020 Shawna MacNabb. All rights reserved.
//

import UIKit

extension UIImage {
    func toJPEGDataWithCompression(compressionRatio: CGFloat) -> Data? {
        return autoreleasepool(invoking: { [weak self] () -> Data? in
            guard let sSelf = self else { return nil }
            return sSelf.jpegData(compressionQuality: compressionRatio)
        })
    }
}
