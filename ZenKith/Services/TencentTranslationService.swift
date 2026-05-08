import Foundation
import CryptoKit

final class TencentTranslationService {
    
    private struct TMTResponse: Decodable {
        struct Response: Decodable {
            let TargetText: String
            let Source: String?
            let Target: String?
            let RequestId: String?
            let Error: TMTApiError?
        }
        let Response: Response
    }
    
    private struct TMTApiError: Decodable {
        let Code: String
        let Message: String
    }
    
    enum TMTError: LocalizedError {
        case invalidCredentials
        case requestFailed(String)
        case apiError(String)
        case noData
        
        var errorDescription: String? {
            switch self {
            case .invalidCredentials: return "请先在设置中配置腾讯云 SecretId 和 SecretKey"
            case .requestFailed(let msg): return "请求失败: \(msg)"
            case .apiError(let msg): return msg
            case .noData: return "未收到翻译结果"
            }
        }
    }
    
    private let secretId: String
    private let secretKey: String
    private let sourceLanguage: String
    private let targetLanguage: String
    private let session: URLSession
    
    init(secretId: String, secretKey: String, source: String, target: String) {
        self.secretId = secretId
        self.secretKey = secretKey
        self.sourceLanguage = source
        self.targetLanguage = target
        self.session = URLSession(configuration: .ephemeral)
    }
    
    func translate(_ text: String) async throws -> String {
        guard !secretId.isEmpty, !secretKey.isEmpty else {
            throw TMTError.invalidCredentials
        }
        
        let service = "tmt"
        let host = "tmt.tencentcloudapi.com"
        let region = "ap-guangzhou"
        let action = "TextTranslate"
        let version = "2018-03-21"
        let algorithm = "TC3-HMAC-SHA256"
        
        let payload: [String: Any] = [
            "SourceText": text,
            "Source": sourceLanguage,
            "Target": targetLanguage,
            "ProjectId": 0
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        
        // Timestamps
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStamp = dateFormatter.string(from: Date())
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let timestamp = dateFormatter.string(from: Date())
        
        // Step 1: Canonical Request
        let httpMethod = "POST"
        let canonicalURI = "/"
        let canonicalQueryString = ""
        let canonicalHeaders = "content-type:application/json\nhost:\(host)\n"
        let signedHeaders = "content-type;host"
        let hashedPayload = SHA256.hash(data: payloadData).hexString
        
        let canonicalRequest = """
        \(httpMethod)
        \(canonicalURI)
        \(canonicalQueryString)
        \(canonicalHeaders)
        \(signedHeaders)
        \(hashedPayload)
        """
        
        // Step 2: String to Sign
        let credentialScope = "\(dateStamp)/\(service)/tc3_request"
        let hashedCanonicalRequest = SHA256.hash(data: Data(canonicalRequest.utf8)).hexString
        
        let stringToSign = """
        \(algorithm)
        \(timestamp)
        \(credentialScope)
        \(hashedCanonicalRequest)
        """
        
        // Step 3: Signature
        let signature = calculateSignature(stringToSign: stringToSign, dateStamp: dateStamp, service: service)
        
        // Step 4: Authorization
        let authorization = "\(algorithm) Credential=\(secretId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        
        // Build request
        var request = URLRequest(url: URL(string: "https://\(host)")!)
        request.httpMethod = httpMethod
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue("TMT-Swift-Client", forHTTPHeaderField: "X-TC-Action")
        request.setValue(timestamp, forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue(version, forHTTPHeaderField: "X-TC-Version")
        request.setValue(region, forHTTPHeaderField: "X-TC-Region")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = payloadData
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            if let errorResponse = try? JSONDecoder().decode(TMTResponse.self, from: data) {
                throw TMTError.apiError(errorResponse.Response.Error?.Message ?? "未知错误")
            }
            throw TMTError.requestFailed("HTTP \(httpResponse.statusCode)")
        }
        
        let decoded = try JSONDecoder().decode(TMTResponse.self, from: data)
        
        if let apiError = decoded.Response.Error {
            throw TMTError.apiError(apiError.Message)
        }
        
        guard !decoded.Response.TargetText.isEmpty else {
            throw TMTError.noData
        }
        
        return decoded.Response.TargetText
    }
    
    func translateBatch(
        _ texts: [String],
        onProgress: @escaping (Int) -> Void
    ) async throws -> [String] {
        var results: [String] = []
        results.reserveCapacity(texts.count)
        
        for (index, text) in texts.enumerated() {
            do {
                let translated = try await translate(text)
                results.append(translated)
                onProgress(index)
            } catch {
                throw error
            }
            
            // Rate limiting: 5 requests/sec, so sleep 250ms between requests
            if index < texts.count - 1 {
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        
        return results
    }
    
    // MARK: - TC3-HMAC-SHA256 Signing
    
    private func calculateSignature(stringToSign: String, dateStamp: String, service: String) -> String {
        let secretKeyData = Data("TC3\(secretKey)".utf8)
        let dateKey = HMAC<SHA256>.authenticationCode(for: Data(dateStamp.utf8), using: SymmetricKey(data: secretKeyData))
        let serviceKey = HMAC<SHA256>.authenticationCode(for: Data("\(service)".utf8), using: SymmetricKey(data: Data(dateKey)))
        let signingKey = HMAC<SHA256>.authenticationCode(for: Data("tc3_request".utf8), using: SymmetricKey(data: Data(serviceKey)))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: Data(signingKey)))
        
        return Data(signature).hexString
    }
}

// MARK: - Helpers

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
