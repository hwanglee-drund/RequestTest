//
//  DRequestError.swift
//  Request
//
//  Created by Shawna MacNabb on 6/19/20.
//  Copyright © 2020 Shawna MacNabb. All rights reserved.
//

import Foundation

public enum DRequestErrorCode: Int {
    // default
    case defaultError = 1000
    case noConnectionError = 1001
    case requestError = 1002
    case uploadFailedError = 1003
    case requestCanceled = 1004
}
