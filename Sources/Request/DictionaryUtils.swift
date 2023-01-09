//
//  DictionaryUtils.swift
//  Drund
//
//  Created by Mike Donahue on 2/16/17.
//  Copyright © 2017 Drund. All rights reserved.
//

import Foundation

/**
 * Contains helpful utilities related to dictionaries
 */ class DictionaryUtils {
    /**
     * Merges parameters into a default dictionary.
     * - Property dictionary1: Dictionary of parameters to merge onto the first dictionary.
     * - Property dictionary2: Dictionary to merge parameters on to.
     * - Returns: A merged `[String:Any]` Dictionary
     */
    static func mergeDictionary(_ dictionary1: [String: Any], withDictionary dictionary2: [String: Any]) -> [String: Any] {
        var parameters = dictionary2
        
        for (key, value) in dictionary1 {
            if let array = value as? [Any] {
                parameters[key] = array
            } else if let dict = value as? [String: Any] {
                parameters[key] = dict
            } else if let bool = value as? Bool {
                parameters[key] = bool
            } else if let url = value as? URL {
                parameters[key] = url
            } else {
                parameters[key] = String(describing: value)
            }
        }
        
        return parameters
    }
    
    /**
     * Merges parameters onto a dictionary.
     * - Property dictionary1: Dictionary of parameters to merge onto the first dictionary.
     * - Property dictionary2: Dictionary to merge parameters on to.
     * - Returns: A merged `[String:String]` Dictionary
     */
    static func mergeDictionary(_ dictionary1: [String: Any], withStringDictionary dictionary2: [String: String]) -> [String: String] {
        var parameters = dictionary2
        
        for (key, value) in dictionary1 {
            parameters[key] = String(describing: value)
        }
        
        return parameters
    }
}
