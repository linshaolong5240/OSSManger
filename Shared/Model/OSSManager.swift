//
//  OSSManager.swift
//  OSSManger
//
//  Created by teenloong on 2022/5/7.
//

import Foundation
import Combine
import SwiftUI
import AliyunOSSiOS

public typealias OSSObjectKey = String

//https://help.aliyun.com/document_detail/31837.htm?spm=a2c4g.11186623.0.0.e3263e06q9eXJK#concept-zt4-cvy-5db
public struct CWOSSRegion {
    public var regionID: String
    public var endpoint: String
    public var endpointURL: String { "https://\(endpoint)"}
    public static let beijing: CWOSSRegion = .init(regionID: "oss-cn-beijing", endpoint: "oss-cn-beijing.aliyuncs.com")
}

extension OSSClientConfiguration {
    public static var `default`: OSSClientConfiguration {
        let config = OSSClientConfiguration()
        config.maxRetryCount = 1
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return config
    }
}

@available(iOS 13.0, *)
public class CWOSSManager {
    public let bucketName: String
    public let client: OSSClient
    @Published public var uploadProgress: Double = 0.0
    @Published public var downloadProgress: Double = 0.0

    public init(region: CWOSSRegion, bucketName: String, clientConfiguration: OSSClientConfiguration = .default) {
        let credential = OSSAuthCredentialProvider.init {
            let tcs = OSSTaskCompletionSource<CWOSSConfigResponse>()
            CW.request(action: CWOSSConfigAction()) { result in
                switch result {
                case .success(let response):
                    tcs.setResult(response)
                case .failure(let error):
                    tcs.setError(error)
                }
            }
            tcs.task.waitUntilFinished()
            guard tcs.task.error == nil else {
                #if DEBUG
                print("get token error: \(tcs.task.error!)")
                #endif
                return nil
            }
            guard let data =  tcs.task.result?.data else {
                return nil
            }
            let token = OSSFederationToken()
            token.tAccessKey = data.access_key_id
            token.tSecretKey = data.access_key_secret
            token.tToken = data.security_token
            token.expirationTimeInGMTFormat = data.expiration
            return token
        }
        client = OSSClient.init(endpoint: region.endpointURL, credentialProvider: credential, clientConfiguration: clientConfiguration)
        
        self.bucketName = bucketName
    }
    
    private func updateUploadProgress(bytesSent: Int64, totalByteSent: Int64, totalBytesExpectedToSend: Int64) {
        #if DEBUG
        print("bytesSent: \(bytesSent), totalByteSent: \(totalByteSent), totalBytesExpectedToSend: \(totalBytesExpectedToSend)")
        #endif
        uploadProgress = Double(bytesSent / totalByteSent)
    }
    
    private func updateDownloadProgress(bytesSent: Int64, totalByteSent: Int64, totalBytesExpectedToSend: Int64) {
        #if DEBUG
        print("bytesSent: \(bytesSent), totalByteSent: \(totalByteSent), totalBytesExpectedToSend: \(totalBytesExpectedToSend)")
        #endif
        downloadProgress = Double(bytesSent / totalByteSent)
    }
    
    public func getBucketInfo(completionHandler: @escaping (Result<OSSGetBucketInfoResult, Error>) -> Void) {
        let request = OSSGetBucketInfoRequest()
        request.bucketName = bucketName
        let task = client.getBucketInfo(request)
        task.continue({ task in
            guard task.error == nil else {
                completionHandler(.failure(task.error!))
                return nil
            }
            completionHandler(.success(task.result as! OSSGetBucketInfoResult))
            return nil
        })
    }
        
    public func upload(from fileURL: URL, objectKey: OSSObjectKey? = nil, prefix: String? = nil, completionHandler: @escaping (Result<OSSObjectKey, Error>) -> Void) {
        let request = OSSPutObjectRequest()
        request.bucketName = bucketName
        request.uploadingFileURL = fileURL
        request.uploadProgress = updateUploadProgress
        // 配置可选字段。
        request.contentType = "application/octet-stream"
        request.contentMd5 = OSSUtil.base64Md5(forFileURL: fileURL)
        let key = "\(prefix ?? "")\(objectKey ?? request.contentMd5)"
        request.objectKey = key
//         request.contentEncoding = @"";
//         request.contentDisposition = @"";
//         可以在上传文件时设置文件元数据或者HTTP头部。
//         request.objectMeta = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"value1", @"x-oss-meta-name1", nil];
        
        let task = client.putObject(request)
        task.continue({ task in
            guard task.error == nil else {
                completionHandler(.failure(task.error!))
                return nil
            }
            completionHandler(.success(key))
            return nil
        })
        
//        task.waitUntilFinished()
//        task.cancel
    }
    
    public func upload(from data: Data, objectKey: OSSObjectKey? = nil, prefix: String? = nil, completionHandler: @escaping (Result<OSSObjectKey, Error>) -> Void) {
        let request = OSSPutObjectRequest()
        request.bucketName = bucketName
        request.uploadingData = data
        request.uploadProgress = updateUploadProgress
        // 配置可选字段。
        request.contentType = "application/octet-stream"
        request.contentMd5 = OSSUtil.base64Md5(for: data)
        let key = "\(prefix ?? "")\(objectKey ?? request.contentMd5)"
        request.objectKey = key
//         request.contentEncoding = @"";
//         request.contentDisposition = @"";
//         可以在上传文件时设置文件元数据或者HTTP头部。
//         request.objectMeta = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"value1", @"x-oss-meta-name1", nil];
        
        let task = client.putObject(request)
        task.continue({ task in
            guard task.error == nil else {
                completionHandler(.failure(task.error!))
                return nil
            }
            completionHandler(.success(key))
            return nil
        })
        
//        task.waitUntilFinished()
//        task.cancel
    }
    
    public func download(objectKey: String, completionHandler: @escaping (Result<OSSGetObjectResult, Error>) -> Void) {
        let request = OSSGetObjectRequest()
        request.bucketName = bucketName
        request.objectKey = objectKey
        request.downloadProgress = updateDownloadProgress
        
        let task = client.getObject(request)
        task.continue({ task in
            guard task.error == nil else {
                completionHandler(.failure(task.error!))
                return nil
            }
            completionHandler(.success(task.result as! OSSGetObjectResult))
            return nil
        })
//        task.waitUntilFinished()
//        task.cancel
    }
        
}

@available(iOS 13.0, *)
extension CWOSSManager {
    public func getBucketInfoPublisher() -> Future<OSSGetBucketInfoResult, Error> {
        let request = OSSGetBucketInfoRequest()
        request.bucketName = bucketName
        
        let task = client.getBucketInfo(request)

        return Future { promise in
            task.continue({ task in
                guard task.error == nil else {
                    promise(.failure(task.error!))
                    return nil
                }
                promise(.success(task.result as! OSSGetBucketInfoResult))
                return nil
            })
        }
    }
    
    public func uploadPublisher(from fileURL: URL, objectKey: OSSObjectKey? = nil, prefix: String? = nil) -> Future<OSSObjectKey, Error> {
        let request = OSSPutObjectRequest()
        request.bucketName = bucketName
        request.uploadingFileURL = fileURL
        request.uploadProgress = updateUploadProgress
        // 配置可选字段。
        request.contentType = "application/octet-stream"
        request.contentMd5 = OSSUtil.base64Md5(forFileURL: fileURL)
        let key = "\(prefix ?? "")\(objectKey ?? request.contentMd5)"
        request.objectKey = key
//         request.contentEncoding = @"";
//         request.contentDisposition = @"";
//         可以在上传文件时设置文件元数据或者HTTP头部。
//         request.objectMeta = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"value1", @"x-oss-meta-name1", nil];
        
        let task = client.putObject(request)
        
        return Future { promise in
            task.continue({ task in
                guard task.error == nil else {
                    promise(.failure(task.error!))
                    return nil
                }
                promise(.success(key))
                return nil
            })
        }
    }
    
    public func uploadPublisher(from data: Data, objectKey: OSSObjectKey? = nil, prefix: String? = nil) -> Future<OSSObjectKey, Error> {
        let request = OSSPutObjectRequest()
        request.bucketName = bucketName
        request.uploadingData = data
        request.uploadProgress = updateUploadProgress
        // 配置可选字段。
        request.contentType = "application/octet-stream"
        request.contentMd5 = OSSUtil.base64Md5(for: data)
        let key = "\(prefix ?? "")\(objectKey ?? request.contentMd5)"
        request.objectKey = key
//         request.contentEncoding = @"";
//         request.contentDisposition = @"";
//         可以在上传文件时设置文件元数据或者HTTP头部。
//         request.objectMeta = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"value1", @"x-oss-meta-name1", nil];
        
        let task = client.putObject(request)
        
        return Future { promise in
            task.continue({ task in
                guard task.error == nil else {
                    promise(.failure(task.error!))
                    return nil
                }
                promise(.success(key))
                return nil
            })
        }
    }
    
    public func downloadPublisher(objectKey: String) -> Future<OSSGetObjectResult, Error> {
        let request = OSSGetObjectRequest()
        request.bucketName = bucketName
        request.objectKey = objectKey
        request.downloadProgress = updateUploadProgress

        let task = client.getObject(request)
        
        return Future { promise in
            task.continue({ task in
                guard task.error == nil else {
                    promise(.failure(task.error!))
                    return nil
                }
                promise(.success(task.result as! OSSGetObjectResult))
                return nil
            })
        }
    }

}

#if canImport(RxSwift)
import RxSwift
extension CWOSSManager {
    public func getBucketInfoObservable() -> Single<OSSGetBucketInfoResult> {
        let request = OSSGetBucketInfoRequest()
        request.bucketName = bucketName
        
        let task = client.getBucketInfo(request)

        return Single.create { singleObserver in
            task.continue({ task in
                guard task.error == nil else {
                    singleObserver(.failure(task.error!))
                    return nil
                }
                singleObserver(.success(task.result as! OSSGetBucketInfoResult))
                return nil
            })
            
            return Disposables.create {
                request.cancel()
            }
        }
    }
    
    public func uploadObservable(from fileURL: URL, objectKey: OSSObjectKey? = nil, prefix: String? = nil) -> Single<OSSObjectKey> {
        let request = OSSPutObjectRequest()
        request.bucketName = bucketName
        request.uploadingFileURL = fileURL
        request.uploadProgress = updateUploadProgress
        // 配置可选字段。
        request.contentType = "application/octet-stream"
        request.contentMd5 = OSSUtil.base64Md5(forFileURL: fileURL)
        let key = "\(prefix ?? "")\(objectKey ?? request.contentMd5)"
        request.objectKey = key
//         request.contentEncoding = @"";
//         request.contentDisposition = @"";
//         可以在上传文件时设置文件元数据或者HTTP头部。
//         request.objectMeta = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"value1", @"x-oss-meta-name1", nil];
        
        let task = client.putObject(request)
        
        return Single.create { singleObserver in
            task.continue({ task in
                guard task.error == nil else {
                    singleObserver(.failure(task.error!))
                    return nil
                }
                singleObserver(.success(key))
                return nil
            })
            
            return Disposables.create {
                request.cancel()
            }
        }
    }
    
    public func uploadObservable(from data: Data, objectKey: OSSObjectKey? = nil, prefix: String? = nil) -> Single<OSSObjectKey>  {
        let request = OSSPutObjectRequest()
        request.bucketName = bucketName
        request.uploadingData = data
        request.uploadProgress = updateUploadProgress
        // 配置可选字段。
        request.contentType = "application/octet-stream"
        request.contentMd5 = OSSUtil.base64Md5(for: data)
        let key = "\(prefix ?? "")\(objectKey ?? request.contentMd5)"
        request.objectKey = key
//         request.contentEncoding = @"";
//         request.contentDisposition = @"";
//         可以在上传文件时设置文件元数据或者HTTP头部。
//         request.objectMeta = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"value1", @"x-oss-meta-name1", nil];
        
        let task = client.putObject(request)
        
        return Single.create { singleObserver in
            task.continue({ task in
                guard task.error == nil else {
                    singleObserver(.failure(task.error!))
                    return nil
                }
                singleObserver(.success(key))
                return nil
            })
            
            return Disposables.create {
                request.cancel()
            }
        }
    }
    
    public func downloadObservable(objectKey: String) -> Single<OSSGetObjectResult> {
        let request = OSSGetObjectRequest()
        request.bucketName = bucketName
        request.objectKey = objectKey
        request.downloadProgress = updateUploadProgress

        let task = client.getObject(request)
        
        return Single.create { singleObserver in
            task.continue({ task in
                guard task.error == nil else {
                    singleObserver(.failure(task.error!))
                    return nil
                }
                singleObserver(.success(task.result as! OSSGetObjectResult))
                return nil
            })
            
            return Disposables.create {
                request.cancel()
            }
        }
    }
}
#endif
