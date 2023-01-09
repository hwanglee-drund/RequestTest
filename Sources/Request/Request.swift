//
//  Request.swift
//  Drund
//
//  Created by Mike Donahue on 12/9/16.
//  Copyright © 2016 Drund. All rights reserved.
//

import UIKit
import Photos
import Foundation

public class Request {
   private static var shouldShowNoConnectionMessage: Bool = true
   
   /// Custom encoding class required by our POST requests. The default Alamofire encoder was adding characters that weren't needed
   private class Encoding {
      
      /**
       *  @discussion Serialize the parameters for a GET in a way that can be concatenated onto an url
       *  @param dictionary: parameters of the request as a dictionary
       *
       *  @return String: parameters formatted as a string
       */
      static func serializeGET(dictionary: [String: Any]) -> String {
         var param = serialize(dictionary: dictionary)
         if !param.isEmpty {
            param = "?" + param
         }
         return param
      }
      
      /**
       *  @discussion Serialize the parameters for a GET/POST in a way that can be concatenated onto an url or used in the `httpBody`
       *  @param dictionary: parameters of the request as a dictionary
       *
       *  @return String: parameters formatted as a string
       *
       *  @note if used for a POST, the result needs to be turned into `Data`
       */
      static func serialize(dictionary: [String: Any]) -> String {
         var params: [String] = []
         for key in dictionary.keys {
            params += serialize(value: dictionary[key] as Any, withKey: key)
         }
         return params.joined(separator: "&")
      }
      
      private static func serialize(value: Any, withKey: String) -> [String] {
         var components: [String] = []
         if let dictionary = value as? [String: Any] {
            for value in dictionary.values {
               components += serialize(value: value, withKey: "\(withKey)")
            }
         } else if let array = value as? [Any] {
            for value in array {
               components += serialize(value: value, withKey: "\(withKey)")
            }
         } else if let bool = value as? Bool {
            components.append("\(withKey)=\(bool ? "1" : "0")")
         } else if var string = value as? String {
            let allowChars = CharacterSet(charactersIn: "._-")
            let charset = CharacterSet.alphanumerics.union(allowChars)
            string = string.replacingOccurrences(of: "‘", with: "'")
            components.append("\(withKey)=\(string.addingPercentEncoding(withAllowedCharacters: charset) ?? string)")
         } else if let number = value as? NSNumber {
            components.append("\(withKey)=\(number)")
         } else {
            components.append("\(withKey)=\(value)")
         }
         
         return components
      }
   }
   
   /// Default parameters for queries. These should be overwritten using mergeParameters
   fileprivate(set) static var  defaultQueryParameters: [String: Any] = [:]
   
   /// Default headers for queries. These will be sent with every subsequent request no matter what.
   fileprivate(set) static var defaultHeaders: [String: String] = [:]
   
   /// Custom headers for queries. These will also be sent with every request, but you have the option to exlude/ignore them from indiviual requests
   /// if a certain scenario requires that.
   fileprivate(set) static var customHeaders: [String: String] = [:]
   
   static let noConnectionErrorCode = -1
   
   static let requestSession = URLSession(configuration: .default)
   
   /// ErrorResponse container.
   //    public struct Response {
   //        var success: Bool
   //        var code: Int
   //        var headers: [AnyHashable: Any]
   //        var url: String
   //        var json: [String:Any]?
   //        var array: [Any]?
   //    }
   
   /// Represents a base response that we can use in code, rather than looking at AlamoFire specific responses
   public class Response {
      /// If the request succeeded
      public var isSuccess: Bool = false
      
      /// The status code of the response, eg. 200, 404
      public var code: Int = 0
      
      /// The headers returned in the response
      public var headers: [AnyHashable: Any] = [:]
      
      /// The url that the request was made do
      public private(set) var url: String = ""
      
      /// the error object from the task
      public var error: Error?
      
      public private(set) var requestErrorCode: DRequestErrorCode?
      
      /// url path components
      public private(set) var pathComponents: [String: String] = [:]
      
      public private(set) var httpURLResponse: HTTPURLResponse?
      
      public private(set) var debugBodyString: String?
      
      /**
       * Extracts response information from the data returned from the request.
       * - Parameter response: Data response from the request. The function will pull relevant information from it.
       */
      
      func responseFailed(code: DRequestErrorCode?) {
         self.requestErrorCode = code
      }
      
      func responseData(response: HTTPURLResponse, data: Data?, error: Error?) {
         code = response.statusCode
         headers = response.allHeaderFields
         httpURLResponse = response
         
         if let responseData = data {
            #if DEBUG || LOCAL
            debugBodyString = String(data: responseData, encoding: .utf8)
            #endif
         }
         
         if let url = response.url {
            self.url = url.absoluteString
            
            // add queryItems to a path components dictionary for easier access since it only gives us back queryItems as an array of URLQueryItem's
            if let urlComponents = URLComponents(string: url.absoluteString) {
               if let items = urlComponents.queryItems {
                  for item in items {
                     pathComponents[item.name] = item.value
                  }
               }
            }
         }
         
         if 200..<300 ~= code {
            isSuccess = true
         }
         
         self.error = error
      }
   }
   
   /// Represents a response from a request that should return a JSON object
   public class JSONResponse: Response {
      public var json: [String: Any] = [:]
      
      /**
       * Extracts response information from the data returned from the request, then try to pull the dictionary from the response
       * - Parameter response: Data response from the request. The function will pull relevant information from it.
       */
      
      override func responseData(response: HTTPURLResponse, data: Data?, error: Error?) {
         super.responseData(response: response, data: data, error: error)
         
         if let data = data {
            do {
               if let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] {
                  json = dictionary
               }
            } catch _ {
               let body = String(data: data, encoding: .utf8)
               //                    let url = response.url
               if body == nil {
                  //  LogError("[Request] error deserializing JSON from request")
                  // Errors.reportError(message: "Error deserializing JSON from request.", extras: ["body": String(describing: body), "url_components": String(describing: url?.pathComponents)])
               }
            }
         }
      }
   }
   
   /// Represents a response from a request that should return a JSON array
   public class ArrayResponse: Response {
      public private(set) var array: [[String: Any]] = []
      
      /**
       *  when uploading images, the response is an array, not a dictionary in an array
       */
      public private(set) var photoIDs: [Int] = []
      
      /**
       * Extracts response information from the data returned from the request, then try to pull the array from the response
       * - Parameter response: Data response from the request. The function will pull relevant information from it.
       */
      
      override func responseData(response: HTTPURLResponse, data: Data?, error: Error?) {
         super.responseData(response: response, data: data, error: error)
         
         if let data = data {
            do {
               if let responseArray = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [[String: Any]] {
                  array = responseArray
               }
            } catch _ {
               let body = String(data: data, encoding: .utf8)
               //                    let url = response.url
               if body == nil {
                  //    LogError("[Request] error deserializing JSON from request")
                  // Errors.reportError(message: "Error deserializing JSON from request.", extras: ["body": String(describing: body), "url_components": String(describing: url?.pathComponents)])
               }
            }
         }
      }
      
      func responseArray(response: HTTPURLResponse, data: Data?, error: Error?) {
         super.responseData(response: response, data: data, error: error)
         
         if let data = data {
            do {
               if let responseArray = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [Int] {
                  photoIDs = responseArray
               }
            } catch _ {
               let body = String(data: data, encoding: .utf8)
               //                    let url = response.url
               if body == nil {
                  //   LogError("[Request] error deserializing JSON from request")
                  //  Errors.reportError(message: "Error deserializing JSON from request.", extras: ["body": String(describing: body), "url_components": String(describing: url?.pathComponents)])
               }
            }
         }
      }
      
      // for unit tests to be able to inject a mock array
      public func setResponseArray(_ array: [[String: Any]]) {
         self.array = array
      }
   }
   
   /**
    * Makes a request to a given endpoint expecting an object in return. Option to send the default community ID
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter sendCommunityId: If the request should send the default community ID (community currently logged into) with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonObject(endpoint: String, sendCommunityId: Bool = true, ignoreCustomHeaders: Bool = false, completion: ((_ response: JSONResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonObject(endpoint: ensureTrailingSlash(endpoint), parameters: nil, headers: nil, sendCommunityId: sendCommunityId, ignoreCustomHeaders: false, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint and a specific community ID expecting an object in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter communityId: Community ID to send with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonObject(endpoint: String, completion: ((_ response: JSONResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonObject(endpoint: ensureTrailingSlash(endpoint), parameters: nil, headers: nil, sendCommunityId: true, ignoreCustomHeaders: false, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint, parameters and option to send the default community ID, expecting an object in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter sendCommunityId: If the request should send the default community ID (community currently logged into) with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonObject(endpoint: String, parameters: [String: Any]?, sendCommunityId: Bool = true, ignoreCustomHeaders: Bool = false, completion: ((_ response: JSONResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonObject(endpoint: ensureTrailingSlash(endpoint), parameters: parameters, headers: nil, sendCommunityId: sendCommunityId, ignoreCustomHeaders: ignoreCustomHeaders, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint, parameters and a specific community ID, expecting an object in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter communityId: Community ID to send with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonObject(endpoint: String, parameters: [String: Any]?, completion: ((_ response: JSONResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonObject(endpoint: ensureTrailingSlash(endpoint), parameters: parameters, headers: nil, sendCommunityId: true, ignoreCustomHeaders: false, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint, with parameters, headers, options to send a community ID, and the specific community ID, expecting an object in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter headers: Extra header parameters for the request
    * - Parameter sendCommunityId: If the request should send the default community ID (community currently logged into) with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonObject(endpoint: String, parameters: [String: Any]?, headers: [String: String]?, sendCommunityId: Bool = true, completion: ((_ response: JSONResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonObject(endpoint: endpoint, parameters: parameters, headers: headers, sendCommunityId: sendCommunityId, ignoreCustomHeaders: false, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint, parameters, headers, and a specific community ID, expecting an object in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter headers: Extra header parameters for the request
    * - Parameter communityId: Community ID to send with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonObject(endpoint: String, parameters: [String: Any]?, headers: [String: String]?, completion: ((_ response: JSONResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonObject(endpoint: endpoint, parameters: parameters, headers: headers, sendCommunityId: true, ignoreCustomHeaders: false, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint, parameters, headers, option to send a community ID, and a specific community ID, expecting an object in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter headers: Extra header parameters for the request
    * - Parameter sendCommunityId: If the request should send the default community ID (community currently logged into) with the request
    * - Parameter communityId: Community ID to send
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonObject(endpoint: String, parameters: [String: Any]?, headers: [String: String]?, sendCommunityId: Bool, ignoreCustomHeaders: Bool, completion: ((_ response: JSONResponse) -> Void)?) -> URLSessionDataTask? {
      
      // Ready a new response
      let jsonResponse = JSONResponse()
      
      // Merge any custom parameters for headers on top of the default ones
      var requestHeaders = defaultHeaders
      
      if !ignoreCustomHeaders {
         requestHeaders = DictionaryUtils.mergeDictionary(customHeaders, withStringDictionary: requestHeaders)
      }
      
      if let newHeaders = headers {
         requestHeaders = DictionaryUtils.mergeDictionary(newHeaders, withStringDictionary: requestHeaders)
      }
      
      let parameters = Request.mergeParameters(customParameters: parameters)
      
      //        // Check if we should send the community id automatically, if so, set the correct
      //        // communit ID
      //        if sendCommunityId == false {
      //            parameters.removeValue(forKey: "community_id")
      //        } else if let id = parameters["community_id"] as? String, Int(id) != communityId {
      //            parameters = DictionaryUtils.mergeDictionary(["community_id": communityId], withDictionary: parameters)
      //        }
      //
      var task: URLSessionDataTask?
      
      let completeEndpoint = endpoint + Encoding.serializeGET(dictionary: parameters)
      
      guard let point = URL(string: completeEndpoint) else {
         jsonResponse.responseFailed(code: .defaultError)
         completion?(jsonResponse)
         return nil
      }
      var urlRequest = URLRequest(url: point)
      urlRequest.httpMethod = "GET"
      urlRequest.allHTTPHeaderFields = requestHeaders
      
      var logParams = parameters
      logParams.removeValue(forKey: "password")
      
      //    LogInfo("\n[Request] endPoint: \(endpoint) parameters: \(logParams) headers: \(requestHeaders.jsonString())\n")
            
      task = Request.requestSession.dataTask(with: urlRequest, completionHandler: { (data, response, error) in
         if let httpResponse = response as? HTTPURLResponse {
            jsonResponse.responseData(response: httpResponse, data: data, error: error)
            //        LogInfo("\n[Request] endPoint: \(endpoint) responseCode: \(jsonResponse.code)")
            
            if jsonResponse.code == 401 {
               NotificationCenter.default.post(name: Notification.Name("catch_401"), object: nil)
            }
            
         } else {
            if let unwrappedError = (error as NSError?) {
               jsonResponse.error = unwrappedError
               
               if unwrappedError.code == NSURLErrorNotConnectedToInternet {
                  jsonResponse.responseFailed(code: .noConnectionError)
               } else if unwrappedError.code == NSURLErrorCancelled {
                  jsonResponse.responseFailed(code: .requestCanceled)
                  return
               } else {
                  jsonResponse.responseFailed(code: .requestError)
               }
            }
         }
         DispatchQueue.main.async {
            completion?(jsonResponse)
         }
      })
      task?.resume()
      
      return task
   }
   
   /**
    * Makes a request to a given endpoint expecting an array in return. Option to send the default community ID
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter sendCommunityId: If the request should send the default community ID (community currently logged into) with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonArray(endpoint: String, ignoreDefaultParameters: Bool = false, ignoreCustomHeaders: Bool = false, completion: ((_ response: ArrayResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonArray(endpoint: ensureTrailingSlash(endpoint), parameters: nil, headers: nil, ignoreDefaultParameters: ignoreDefaultParameters, ignoreCustomHeaders: ignoreCustomHeaders, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint and a specific community ID, expecting an array in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter communityId: Community ID to send with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonArray(endpoint: String, completion: ((_ response: ArrayResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonArray(endpoint: ensureTrailingSlash(endpoint), parameters: nil, headers: nil, ignoreDefaultParameters: false, ignoreCustomHeaders: false, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint, parameters and option to send the default community ID, expecting an array in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter sendCommunityId: If the request should send the default community ID (community currently logged into) with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonArray(endpoint: String, parameters: [String: Any]?, ignoreDefaultParameters: Bool = false, completion: ((_ response: ArrayResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonArray(endpoint: ensureTrailingSlash(endpoint), parameters: parameters, headers: nil, ignoreDefaultParameters: ignoreDefaultParameters, ignoreCustomHeaders: false, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint, parameters and a specific community ID, expecting an array in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter communityId: Community ID to send with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonArray(endpoint: String, parameters: [String: Any]?, communityId: Int, completion: ((_ response: ArrayResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonArray(endpoint: ensureTrailingSlash(endpoint), parameters: parameters, headers: nil, ignoreDefaultParameters: false, ignoreCustomHeaders: false, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint, with parameters, headers, options to send a community ID, and the specific community ID, expecting an array in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter headers: Extra header parameters for the request
    * - Parameter sendCommunityId: If the request should send the default community ID (community currently logged into) with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonArray(endpoint: String, parameters: [String: Any]?, headers: [String: String]?, ignoreDefaultParameters: Bool = false, completion: ((_ response: ArrayResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonArray(endpoint: ensureTrailingSlash(endpoint), parameters: parameters, headers: headers, ignoreDefaultParameters: ignoreDefaultParameters, ignoreCustomHeaders: false, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint, parameters, headers, and a specific community ID, expecting an array in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter headers: Extra header parameters for the request
    * - Parameter communityId: Community ID to send with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonArray(endpoint: String, parameters: [String: Any]?, headers: [String: String]?, completion: ((_ response: ArrayResponse) -> Void)?) -> URLSessionDataTask? {
      return jsonArray(endpoint: ensureTrailingSlash(endpoint), parameters: parameters, headers: headers, ignoreDefaultParameters: false, ignoreCustomHeaders: false, completion: completion)
   }
   
   /**
    * Makes a request to a given endpoint, parameters, headers, option to send a community ID, and a specific community ID, expecting an array in return.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter headers: Extra header parameters for the request
    * - Parameter sendCommunityId: If the request should send the default community ID (community currently logged into) with the request
    * - Parameter communityId: Community ID to send with the request
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func jsonArray(endpoint: String, parameters: [String: Any]?, headers: [String: String]?, ignoreDefaultParameters: Bool = false, ignoreCustomHeaders: Bool, completion: ((_ response: ArrayResponse) -> Void)?) -> URLSessionDataTask? {
      
      // Ready a new response
      let arrayResponse = ArrayResponse()
      
      // Merge any custom parameters for headers on top of the default ones
      var requestHeaders = defaultHeaders
      
      if !ignoreCustomHeaders {
         requestHeaders = DictionaryUtils.mergeDictionary(customHeaders, withStringDictionary: requestHeaders)
      }
      
      if let newHeaders = headers {
         requestHeaders = DictionaryUtils.mergeDictionary(newHeaders, withStringDictionary: requestHeaders)
      }
      
      var finalParameters: [String: Any] = [:]
      
      if ignoreDefaultParameters, let parameters = parameters  {
         finalParameters = parameters
      } else {
         finalParameters = Request.mergeParameters(customParameters: parameters)
      }
      
      // Check if we should send the community id automatically, if so, set the correct
      // communit ID
      //        if sendCommunityId == false {
      //            parameters.removeValue(forKey: "community_id")
      //        } else if let id = parameters["community_id"] as? Int, id != communityId {
      //            parameters["community_id"] = id
      //        }
      //
      
      var task: URLSessionDataTask?
      
      let completeEndpoint = endpoint + Encoding.serializeGET(dictionary: finalParameters)
      
      guard let point = URL(string: completeEndpoint) else {
         arrayResponse.responseFailed(code: .defaultError)
         completion?(arrayResponse)
         return nil
      }
      var urlRequest = URLRequest(url: point)
      urlRequest.httpMethod = "GET"
      urlRequest.allHTTPHeaderFields = requestHeaders
      
      var logParams = finalParameters
      logParams.removeValue(forKey: "password")
      
      //  LogInfo("\n[Request] endPoint: \(endpoint) parameters: \(logParams) headers: \(requestHeaders.jsonString())\n")
      
      task = Request.requestSession.dataTask(with: urlRequest, completionHandler: { (data, response, error) in
         if let httpResponse = response as? HTTPURLResponse {
            //  LogInfo("\n[Request] endPoint: \(endpoint) responseCode: \(arrayResponse.code)")
            
            arrayResponse.responseData(response: httpResponse, data: data, error: error)
            
            if arrayResponse.code == 401 {
               NotificationCenter.default.post(name: Notification.Name("catch_401"), object: nil)
            }
         } else {
            if let unwrappedError = (error as NSError?) {
               arrayResponse.error = unwrappedError
               if unwrappedError.code == NSURLErrorNotConnectedToInternet {
                  arrayResponse.responseFailed(code: .noConnectionError)
               } else if unwrappedError.code == NSURLErrorCancelled {
                  arrayResponse.responseFailed(code: .requestCanceled)
                  return
               } else {
                  arrayResponse.responseFailed(code: .requestError)
               }
            }
         }
         DispatchQueue.main.async {
            completion?(arrayResponse)
         }
      })
      task?.resume()
      return task
   }
   
   /**
    * Makes a POST request to an endpoint expecting a JSON response. Has option to pass the community ID.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter sendCommunityId: If the request should send the current community ID by default
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func post(endpoint: String, ignoreDefaultParameters: Bool = false, ignoreCustomHeaders: Bool = false, completion: ((_ response: JSONResponse) -> Void)?) -> URLSessionDataTask? {
      return post(endpoint: ensureTrailingSlash(endpoint), parameters: nil, headers: nil, ignoreDefaultParameters: ignoreDefaultParameters, ignoreCustomHeaders: ignoreCustomHeaders, completion: completion)
   }
   
   /**
    * Makes a POST request to an endpoint expecting a JSON response. Has option to give parameters and pass the community ID.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter sendCommunityId: If the request should send the current community ID by default
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func post(endpoint: String, parameters: [String: Any]?, ignoreDefaultParameters: Bool = false, ignoreCustomHeaders: Bool = false, completion: ((_ response: JSONResponse) -> Void)?) -> URLSessionDataTask? {
      return post(endpoint: ensureTrailingSlash(endpoint), parameters: parameters, headers: nil, ignoreDefaultParameters: ignoreDefaultParameters, ignoreCustomHeaders: ignoreCustomHeaders, completion: completion)
   }
   
   /**
    * Makes a POST request to an endpoint expecting a JSON response. Has option to give parameters, headers, and pass the community ID.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter headers: Extra header parameters for the request
    * - Parameter sendCommunityId: If the request should send the current community ID by default
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func post(endpoint: String, parameters: [String: Any]?, headers: [String: String]?, ignoreDefaultParameters: Bool = false, ignoreCustomHeaders: Bool = false, completion: ((_ response: JSONResponse) -> Void)?) -> URLSessionDataTask? {
   
//      LogInfo("\n[Request] post endPoint: \(endpoint) parameters: \(String(describing: parameters)) headers: \(String(describing: headers)) ignoreDefaultParameters \(ignoreDefaultParameters) ignoreCustomHeaders: \(ignoreCustomHeaders) \n")
      
      // Ready a new response
      let jsonResponse = JSONResponse()
      
      var requestHeaders = defaultHeaders
      
      if !ignoreCustomHeaders {
         requestHeaders = DictionaryUtils.mergeDictionary(customHeaders, withStringDictionary: requestHeaders)
      }
      
      if let newHeaders = headers {
         requestHeaders = DictionaryUtils.mergeDictionary(newHeaders, withStringDictionary: requestHeaders)
      }
      
      var finalParameters: [String: Any] = [:]
      
      if ignoreDefaultParameters, let parameters = parameters  {
         finalParameters = parameters
      } else {
         finalParameters = Request.mergeParameters(customParameters: parameters)
      }
      
      var task: URLSessionDataTask?
      
      guard let point = URL(string: endpoint) else {
         jsonResponse.responseFailed(code: .defaultError)
         completion?(jsonResponse)
         return nil
      }
      var urlRequest = URLRequest(url: point)
      urlRequest.httpMethod = "POST"
      urlRequest.allHTTPHeaderFields = requestHeaders
      urlRequest.httpBody = Encoding.serialize(dictionary: finalParameters).data(using: .utf8)
      
      var logParams = finalParameters
      logParams.removeValue(forKey: "password")
      
      //  LogInfo("\n[Request] endPoint: \(endpoint) parameters: \(logParams) headers: \(requestHeaders.jsonString())\n")

      task = Request.requestSession.dataTask(with: urlRequest, completionHandler: { (data, response, error) in
         if let httpResponse = response as? HTTPURLResponse {
            jsonResponse.responseData(response: httpResponse, data: data, error: error)
            //   LogInfo("\n[Request] endPoint: \(endpoint) responseCode: \(jsonResponse.code) response: \(jsonResponse.json.jsonString())\n")
            
            if jsonResponse.code == 401 {
               NotificationCenter.default.post(name: Notification.Name("catch_401"), object: nil)
            }
         } else {
            if let unwrappedError = (error as NSError?) {
               jsonResponse.error = unwrappedError
               if unwrappedError.code == NSURLErrorNotConnectedToInternet {
                  jsonResponse.responseFailed(code: .noConnectionError)
               } else if unwrappedError.code == NSURLErrorCancelled {
                  jsonResponse.responseFailed(code: .requestCanceled)
                  return
               } else {
                  jsonResponse.responseFailed(code: .requestError)
               }
            }
         }
         DispatchQueue.main.async {
            completion?(jsonResponse)
         }
      })
      task?.resume()
      
      return task
   }
   
   /**
    * Makes a POST request to an endpoint expecting an Array response. Has option to give parameters, headers, and pass the community ID.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter sendCommunityId: If the request should send the current community ID by default
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func postForArray(endpoint: String, ignoreDefaultParameters: Bool = false, completion: ((_ response: ArrayResponse) -> Void)?) -> URLSessionDataTask? {
      
      return postForArray(endpoint: ensureTrailingSlash(endpoint), parameters: nil, headers: nil, ignoreDefaultParameters: ignoreDefaultParameters, completion: completion)
   }
   
   /**
    * Makes a POST request to an endpoint expecting an Array response. Has option to give parameters, headers, and pass the community ID.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter sendCommunityId: If the request should send the current community ID by default
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func postForArray(endpoint: String, parameters: [String: Any]?, ignoreDefaultParameters: Bool = false, completion: ((_ response: ArrayResponse) -> Void)?) -> URLSessionDataTask? {
      
      return postForArray(endpoint: ensureTrailingSlash(endpoint), parameters: parameters, headers: nil, ignoreDefaultParameters: ignoreDefaultParameters, completion: completion)
   }
   
   /**
    * Makes a POST request to an endpoint expecting an Array response. Has option to give parameters, headers, and pass the community ID.
    * - Parameter endpoint: Endpoint string for the request
    * - Parameter parameters: Query parameters for the request
    * - Parameter headers: Extra header parameters for the request
    * - Parameter sendCommunityId: If the request should send the current community ID by default
    * - Parameter completion: Completeion block. Called when the request finishes
    */
   @discardableResult
   public static func postForArray(endpoint: String, parameters: [String: Any]?, headers: [String: String]?, ignoreDefaultParameters: Bool = false, completion: ((_ response: ArrayResponse) -> Void)?) -> URLSessionDataTask? {
      
      var task: URLSessionDataTask?
      
      let arrayResponse = ArrayResponse()
      
      var requestHeaders = defaultHeaders
      
      requestHeaders = DictionaryUtils.mergeDictionary(customHeaders, withStringDictionary: requestHeaders)
      
      if let newHeaders = headers {
         requestHeaders = DictionaryUtils.mergeDictionary(newHeaders, withStringDictionary: requestHeaders)
      }
      
      var finalParameters: [String: Any] = [:]
      
      if ignoreDefaultParameters, let parameters = parameters  {
         finalParameters = parameters
      } else {
         finalParameters = Request.mergeParameters(customParameters: parameters)
      }
      
      guard let point = URL(string: ensureTrailingSlash(endpoint)) else {
         arrayResponse.responseFailed(code: .defaultError)
         completion?(arrayResponse)
         return nil
      }
      
      var urlRequest = URLRequest(url: point)
      urlRequest.httpMethod = "POST"
      urlRequest.allHTTPHeaderFields = requestHeaders
      
      urlRequest.httpBody = Encoding.serialize(dictionary: finalParameters).data(using: .utf8)
      
      var logParams = finalParameters
      logParams.removeValue(forKey: "password")
      
      //    LogInfo("\n[Request] endPoint: \(endpoint) parameters: \(logParams) headers: \(requestHeaders.jsonString())\n")
      
      task = Request.requestSession.dataTask(with: urlRequest, completionHandler: { (data, response, error) in
         if let httpResponse = response as? HTTPURLResponse {
            arrayResponse.responseData(response: httpResponse, data: data, error: error)
            //      LogInfo("[Request] endPoint: \(endpoint) responseCode: \(arrayResponse.code)")
            
            if arrayResponse.code == 401 {
               NotificationCenter.default.post(name: Notification.Name("catch_401"), object: nil)
            }
         } else {
            if let unwrappedError = (error as NSError?) {
               arrayResponse.error = unwrappedError
               if unwrappedError.code == NSURLErrorNotConnectedToInternet {
                  arrayResponse.responseFailed(code: .noConnectionError)
               } else if unwrappedError.code == NSURLErrorCancelled {
                  arrayResponse.responseFailed(code: .requestCanceled)
                  return
               } else {
                  arrayResponse.responseFailed(code: .requestError)
               }
            }
         }
         
         DispatchQueue.main.async {
            completion?(arrayResponse)
         }
      })
      task?.resume()
      
      return task
   }
   
   /**
    * POST request for multipart form upload.
    * - Parameter endpoint: Endpoint for the request
    * - Parameter extraFormData: Dictionary of extra parameters to add to the request form data
    * - Parameter completion: Completeion handler. Called when the request finishes
    */
   public static func upload(endpoint: String, fileURL: URL, fileKey: String, extraFormData: [String: Any]?, completion: ((_ response: JSONResponse) -> Void)?) {
      
      //   LogInfo("[Request] endPoint: \(endpoint) parameters: \(fileKey)")
      let mergedDic = mergeParameters(customParameters: extraFormData)
      
      let styledEndpoint = endpoint + Encoding.serializeGET(dictionary: mergedDic)
      
      let jsonResponse = JSONResponse()
      let session = URLSession(configuration: .default)
      let request = UploadTaskRequestConstructor.createStandardRequest(styledEndpoint: styledEndpoint, fileURL: fileURL, fileKey: fileKey, extraFormData: extraFormData, defaultHeaders: defaultHeaders)
      
      if let request = request {
         let task = session.dataTask(with: request, completionHandler: { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
               jsonResponse.responseData(response: httpResponse, data: data, error: error)
               
            } else {
               if let unwrappedError = (error as NSError?) {
                  jsonResponse.error = unwrappedError
                  if unwrappedError.code == NSURLErrorNotConnectedToInternet {
                     jsonResponse.responseFailed(code: .noConnectionError)
                  } else if unwrappedError.code == NSURLErrorCancelled {
                     jsonResponse.responseFailed(code: .requestCanceled)
                     return
                  } else {
                     jsonResponse.responseFailed(code: .requestError)
                  }
               }
            }
            
            DispatchQueue.main.async {
               completion?(jsonResponse)
            }
         })
         task.resume()
      } else {
         completion?(jsonResponse)
      }
   }
   
   public static func download(endpoint: String, completion: @escaping ((_ fileURL: URL?, _ errorCode: DRequestErrorCode?, _ underlyingError: Error?) -> Void)) {
      
      //    LogInfo("[Request] download endpoint: \(endpoint)")
      
      if let url = URL(string: endpoint) {
         var urlRequest = URLRequest(url: url)
         urlRequest.httpMethod = "GET"
         urlRequest.allHTTPHeaderFields = defaultHeaders
         
         let task = Request.requestSession.downloadTask(with: urlRequest) { (tempLocalUrl, response, error) in
            if let httpResponse = response as? HTTPURLResponse, let tempLocalUrl = tempLocalUrl {
               if httpResponse.statusCode == 200 {
                  // we have to move the file somewhere else because the location sent back
                  // from nsurlsession is removed after the completion handler is finished
                  let localURL = FileManager.default.temporaryDirectory
                  if let filename = httpResponse.suggestedFilename {
                     
                     let fullURL = localURL.appendingPathComponent(filename, isDirectory: false)
                     let isFileMoved = FileManagerUtils.moveFileItem(at: tempLocalUrl, to: fullURL)
                     // something went wrong
                     isFileMoved ? completion(fullURL, nil, nil) : completion(nil, .uploadFailedError, nil)
                  } else {
                     // something went wrong
                     //  LogError("[Request] downlaod file: cound't find filename")
                     completion(nil, .uploadFailedError, nil)
                  }
               } else {
                  // 200 was not received
                  if let error = error {
                     // something went wrong
                     completion(nil, .uploadFailedError, error)
                  }
                  // something went wrong
                  completion(nil, .uploadFailedError, nil)
               }
            } else {
               if let unwrappedError = (error as NSError?) {
                  if unwrappedError.code == NSURLErrorNotConnectedToInternet {
                     completion(nil, .noConnectionError, unwrappedError)
                  } else if unwrappedError.code == NSURLErrorCancelled {
                     completion(nil, .requestCanceled, unwrappedError)
                  } else {
                     completion(nil, .requestError, unwrappedError)
                  }
               } else {
                  // something unrecoverable happened
                  completion(nil, .uploadFailedError, nil)
               }
            }
         }
         task.resume()
      }
   }
   
   /**
    * Append a slash to the end of an endpoint that is missing a slash during a request.
    * Send a sentry error.
    * - Parameter endpoint: Endpoint for the request
    */
   private static func ensureTrailingSlash(_ endpoint: String) -> String {
      if endpoint.hasSuffix("/") == false {
         //  Errors.reportWarning(message: "Endpoint missing trailing slash.", extras: ["endpoint": endpoint])
         return endpoint.appending("/")
      }
      return endpoint
   }
   
   /**
    * Processes a 401 response. The should only occur with OAuth authentication.
    * - Parameter response: Response from the request.
    */
   //  private static func process401Response() {
   // Check 401 response.
   // NOTE: Right now, we're redirecting to login all the time, but at some point we may
   // want to check specific error codes and do something differently (ie: Refresh the access
   // token and retry the request). As of writing this, our OAuth token expiration is 6 months
   // AND we refresh the token every app load, so there is no chance the access token would
   // expire during the app's lifecycle. If the device token was revoked, then we want to
   // push them back to login anyways.
   //  AuthHandler.respondToUnauthorizedRequest()
   //  }
   
   /**
    * Updates the sessionId pulled from response headers if the sessionid is different than what is currently stored.
    * - Parameter urlResponse: HTTPURLResponse from the request.
    */
   //    private static func updateSessionId(urlResponse: HTTPURLResponse?) {
   //        guard let response = urlResponse else {
   //            return
   //        }
   //
   //        if response.allHeaderFields.keys.contains("Set-Cookie") {
   //            if let header = response.allHeaderFields["Set-Cookie"] as? String {
   //                let results = header.matchingStrings(regex: "sessionid=(.*?);")
   //
   //                if let result = results.first {
   //                    if result.count > 1 && result[1].isEmpty == false {
   //                        Session.shared.sessionId = result[1]
   //                    }
   //                }
   //            }
   //        }
   //    }
   
   /**
    * Merges parameter on top of the defaults.
    * - Parameter customParameters: Parameters to merge. Will overwrite defaultQueryParameters
    */
   public static func mergeParameters(customParameters: [String: Any]?) -> [String: Any] {
      var parameters = Request.defaultQueryParameters
      
      if let newParams = customParameters {
         parameters = DictionaryUtils.mergeDictionary(newParams, withDictionary: parameters)
      }
      
      return parameters
   }
   
   /**
    //    * Merges parameter on top of the defaults.
    //    * - Parameter customParameters: Parameters to merge. Will overwrite defaultQueryParameters
    //    */
   //   public static func mergeHeaders(customParameters: [String: Any]?) -> [String: String] {
   //      var parameters = Request.defaultHeaders
   //
   //      if let newParams = customParameters {
   //         parameters = DictionaryUtils.mergeDictionary(newParams, withStringDictionary: parameters)
   //      }
   //
   //      return parameters
   //   }
}

/**
 * Request extension to OAuth refresh token functionality since it's being checked in the root
 * `get()` and `set()` functions.
 */
extension Request {
   /**
    * Refresh OAuth is using it's own request to avoid sending the default headers/parameters that we'd want with typical requests
    */
   public static func refreshOAuthToken(refreshToken: String, endpoint: String, oauthHeader: String, parameters: [String: Any]? = nil, completion: @escaping ((String?, String?, Request.JSONResponse) -> Void)) {
//      LogInfo("[Request] refreshOAuthToken")
      
      // Declare Parameters
      
      var refreshParameters = [
         "refresh_token": refreshToken,
         "grant_type": "refresh_token"
         //    "test_alert_email": "on"
      ]
      
      if let parameters = parameters {
         refreshParameters = DictionaryUtils.mergeDictionary(parameters, withStringDictionary: refreshParameters)
      }
      
      // Declare Headers
      
      var requestHeaders = defaultHeaders
      
      let headers = ["Authorization": oauthHeader]
      
      requestHeaders = DictionaryUtils.mergeDictionary(headers, withStringDictionary: requestHeaders)
      
      // Setup Reuqest Session with the above properties
      
      let jsonResponse = JSONResponse()
      
      var task: URLSessionDataTask?
      guard let queryParamsWithEndpoint = URL(string: endpoint) else { return }
      
      var urlRequest = URLRequest(url: queryParamsWithEndpoint)
      urlRequest.httpMethod = "POST"
      urlRequest.allHTTPHeaderFields = requestHeaders
      urlRequest.httpBody = Encoding.serialize(dictionary: refreshParameters).data(using: .utf8)
      
      //  LogInfo("[Request] endPoint: \(Endpoints.Auth.oauthRefreshToken) parameters: \(queryParameters) headers: \(headers)")
      
      var accessToken: String?
      var refreshToken: String?

      task = Request.requestSession.dataTask(with: urlRequest, completionHandler: { (data, response, error) in
//         LogInfo("[Request] refreshOAuthToken requestSession urlRequest: \(urlRequest)")
         if let httpResponse = response as? HTTPURLResponse {
            jsonResponse.responseData(response: httpResponse, data: data, error: error)
//            LogInfo("[Request] refreshOAuthToken requestSession responseData: \(httpResponse)")
             
            if jsonResponse.isSuccess {
               accessToken = jsonResponse.json["access_token"] as? String
               refreshToken = jsonResponse.json["refresh_token"] as? String
               
               // Set request modules Authorization header
               if let accessToken = accessToken {
                  setOAuthTokenHeader(accessToken: accessToken)
               }
            }
         } else {
            if let unwrappedError = (error as NSError?) {
               jsonResponse.error = unwrappedError
               if unwrappedError.code == NSURLErrorNotConnectedToInternet {
                  jsonResponse.responseFailed(code: .noConnectionError)
               } else if unwrappedError.code == NSURLErrorCancelled {
                  jsonResponse.responseFailed(code: .requestCanceled)
                  return
               } else {
                  jsonResponse.responseFailed(code: .requestError)
               }
            }
         }
         DispatchQueue.main.async {
            completion(accessToken, refreshToken, jsonResponse)
         }
      })
      task?.resume()
   }
   
   public static func defaultHeadersContainValueWithKey(_ key: String, andValue value: String) -> Bool {
      return defaultHeaders[key] == value
   }
   
   public static func addDefaultHeaderWithKey(_ key: String, andValue value: String) {
      defaultHeaders = DictionaryUtils.mergeDictionary([key: value], withStringDictionary: Request.defaultHeaders)
   }
   
   public static func removeDefaultHeaderForKey(_ key: String) {
      if defaultHeaders.keys.contains(key) {
         defaultHeaders.removeValue(forKey: key)
      }
   }
   
   public static func addCustomHeaderWithKey(_ key: String, andValue value: String) {
      customHeaders = DictionaryUtils.mergeDictionary([key: value], withStringDictionary: Request.customHeaders)
   }
   
   public static func removeCustomHeaderForKey(_ key: String) {
      if customHeaders.keys.contains(key) {
         customHeaders.removeValue(forKey: key)
      }
   }
   
   public static func addDefaultParameterWithKey(_ key: String, andValue value: AnyHashable) {
      defaultQueryParameters = DictionaryUtils.mergeDictionary([key: value], withDictionary: defaultQueryParameters)
   }
   
   public static func removeDefaultParameterForKey(_ key: String) {
      if defaultQueryParameters.keys.contains(key) {
         defaultQueryParameters.removeValue(forKey: key)
      }
   }
   
   /**
    * Set current access token in header.
    * - Parameter accessToken: OAuth Access token to set in the default request headers
    */
   public static func setOAuthTokenHeader(accessToken: String) {
      addDefaultHeaderWithKey("Authorization", andValue: "Bearer \(accessToken)")
   }
   
   /**
    * Clear OAuth token in header.
    */
   public static func clearOAuthTokenHeader() {
      removeDefaultHeaderForKey("Authorization")
   }
}
extension Request {
   public class UploadOperationQueue: OperationQueue {
      override public func cancelAllOperations() {
         for case let operation as Request.MultiMediaUploadOperation in operations {
            operation.cancel()
         }
         super.cancelAllOperations()
      }
   }
   
   public class MultiMediaUploadOperation: AsyncOperation {
      
      // define properties to hold everything that you'll supply when you instantiate
      // this object and will be used when the request finally starts
      //
      // in this example, I'll keep track of (a) URL; and (b) closure to call when request is done
      
      var endpoint: String
      let item: FileUploadItem
      var extraFormData = [String: Any]()
      
      fileprivate var formData: [String: Any] = [:]
      
      // we'll also keep track of the resulting request operation in case we need to cancel it later
      
      let response = ArrayResponse()
      var dataTask: URLSessionDataTask?
      
      var uploadRequest: UploadRequest
      
      // define init method that captures all of the properties to be used when issuing the request
      
      init(uploadRequest: UploadRequest, item: FileUploadItem) {
         self.uploadRequest = uploadRequest
         self.extraFormData = uploadRequest.extraParameters ?? [String: Any]()
         
         //  LogInfo("[Request] album upload endPoint: \(uploadRequest.endpoint)")
         
         if let idData = "\(uploadRequest.currentCommunityId)".data(using: .utf8) {
            formData["community_id"] = idData
         }
         
         self.endpoint = ""
         self.item = item
         
         super.init()
         
         switch uploadRequest.type {
         case .file:
            if let key = uploadRequest.toFolderID {
               extraFormData["folder_key"] = key
            }
            break
         case .album:
            if item.isFromPost {
               extraFormData["is_upload_only"] = "on"
            }
            break
         default:
            break
         }
         
         endpoint = ensureTrailingSlash(uploadRequest.endpoint) + Encoding.serializeGET(dictionary: Request.defaultQueryParameters)
      }
      
      // when the operation actually starts, this is the method that will be called
      /**
       *  NOTE: progress needs to be marked failed/succeeded and then completion handler can be called.  CompleteOperation should be the LAST thing called
       */
      override public func main() {
         
         // If uploading an array of items, we need the key 'files', if only uploading one item (stream) use 'file'
         var fileKey = ""
         if uploadRequest.type == .stream {
            fileKey = "file"
         } else {
            fileKey = "files"
         }
         
         if !uploadRequest.isBackgroundUpload {
            let request = UploadTaskRequestConstructor.createStandardRequest(styledEndpoint: endpoint, fileURL: item.fileURL, fileKey: fileKey, extraFormData: extraFormData, defaultHeaders: defaultHeaders)
            if let request = request, let session = UploadRequestManager.shared.uploadRequestSession {
               dataTask = session.uploadTask(with: request, from: request.httpBody!)
               dataTask?.resume()
            }
         } else {
            let request = UploadTaskRequestConstructor.createRequestForBackgroundUpload(styledEndpoint: endpoint, defaultHeaders: defaultHeaders)
            if let returnedRequest = request.request, let session = UploadRequestManager.shared.uploadRequestSession {
               // save the data to disk so we can point the uploadTask to the file data to upload
               if let savedDataLocation = UploadTaskRequestConstructor.writeMultipartDataToDisk(fileURL: item.fileURL, fileKey: fileKey, extraFormData: extraFormData, boundaryId: request.boundaryId) {
                  dataTask = session.uploadTask(with: returnedRequest, fromFile: savedDataLocation)
                  UploadRequestManager.shared.notifyListenersDidSaveUploadData(savedDataLocation, uploadRequest: uploadRequest)
                  UploadRequestManager.shared.notifyListenersStatusChanged(.staged, uploadRequest: uploadRequest)
                  dataTask?.resume()
               }
            } else {
               // todo something went wrong that should never happen since we have complete control over the request params
               item.setItemProgressFailed()
            }
         }
      }
      
      // we'll also support canceling the request, in case we need it
      
      override public func cancel() {
         //    LogInfo("[Request] task cancelled")
         dataTask?.cancel()
         
         super.cancel()
      }
   }
}

extension Dictionary {
   func jsonString(prettyPrint: Bool = false) -> String {
      if let json = try? JSONSerialization.data(withJSONObject: self, options: prettyPrint ? [.prettyPrinted] : []) {
         if let jsonString = String(data: json, encoding: .utf8) {
            return jsonString.replacingOccurrences(of: "\\/", with: "/")
         }
      }
      
      return ""
   }
   
   var escapedJSONString: String {
      return jsonString(prettyPrint: false).replacingOccurrences(of: "\"", with: "\\\"")
   }
   
   func value(forKeyPath keyPath: String) -> Any? {
      let d = self as NSDictionary
      return d.value(forKeyPath: keyPath) as Any?
   }
   
}

extension Array {
   func jsonString() -> String {
      if let jsonArray = self as? [[String: Any]] {
         var pieces: [String] = []
         for dict in jsonArray {
            pieces.append(dict.jsonString())
         }
         return String(format: "[%@]", pieces.joined(separator: ","))
      }
      return "Array.jsonString error: Array couldn't be cast as [[String:Any]]"
   }
}
