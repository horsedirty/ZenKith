import Foundation
import CryptoKit

final class TencentTranslationService {

    private struct TMTResponse: Decodable {
        struct Response: Decodable {
            let TargetText: String?
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
        self.secretId = secretId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let endpoint = "https://tmt.tencentcloudapi.com"
        let action = "TextTranslate"
        let version = "2018-03-21"
        let algorithm = "TC3-HMAC-SHA256"

        // JSON body
        let payloadDict: [String: Any] = [
            "SourceText": text,
            "Source": sourceLanguage,
            "Target": targetLanguage,
            "ProjectId": 0
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict, options: .sortedKeys)
        let payloadHash = hexString(SHA256.hash(data: payloadData))

        // Timestamps
        let now = Date()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        let dateStamp = fmt.string(from: now)
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let timestampStr = fmt.string(from: now)
        let unixTimestamp = Int(now.timeIntervalSince1970)

        // Step 1 — Canonical Request
        let httpMethod = "POST"
        let canonicalURI = "/"
        let canonicalQueryString = ""
        let canonicalHeaders = "content-type:application/json\nhost:\(host)\n"
        let signedHeaders = "content-type;host"

        let canonicalRequest = httpMethod + "\n"
            + canonicalURI + "\n"
            + canonicalQueryString + "\n"
            + canonicalHeaders + "\n"
            + signedHeaders + "\n"
            + payloadHash

        let hashedCanonicalRequest = hexString(SHA256.hash(data: Data(canonicalRequest.utf8)))

        // Step 2 — String to Sign
        let credentialScope = "\(dateStamp)/\(service)/tc3_request"

        let stringToSign = algorithm + "\n"
            + timestampStr + "\n"
            + credentialScope + "\n"
            + hashedCanonicalRequest

        // Step 3 — Derive signing key
        let kDate = hmacSHA256(key: Data("TC3\(secretKey)".utf8), data: Data(dateStamp.utf8))
        let kService = hmacSHA256(key: kDate, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("tc3_request".utf8))

        // Step 4 — Signature
        let signatureData = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8))
        let signature = hexString(signatureData)

        // Step 5 — Authorization header
        let authorization = "\(algorithm) Credential=\(secretId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        // Build HTTP request
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(action, forHTTPHeaderField: "X-TC-Action")
        request.setValue(String(unixTimestamp), forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue(version, forHTTPHeaderField: "X-TC-Version")
        request.setValue("ap-guangzhou", forHTTPHeaderField: "X-TC-Region")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = payloadData

        // Execute
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMTError.requestFailed("无效的响应")
        }

        let body = String(data: data, encoding: .utf8) ?? ""

        if httpResponse.statusCode != 200 {
            if let err = try? JSONDecoder().decode(TMTResponse.self, from: data),
               let msg = err.Response.Error?.Message {
                throw TMTError.apiError(msg)
            }
            throw TMTError.requestFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let decoded: TMTResponse
        do {
            decoded = try JSONDecoder().decode(TMTResponse.self, from: data)
        } catch {
            throw TMTError.requestFailed("解析失败: \(error.localizedDescription)\nRaw: \(body.prefix(500))")
        }

        if let apiError = decoded.Response.Error {
            let debugInfo = """
            CanonicalRequest:
            \(canonicalRequest)

            StringToSign:
            \(stringToSign)

            Signature: \(signature)
            """
            throw TMTError.requestFailed("\(apiError.Message)\n\n调试信息:\n\(debugInfo)")
        }

        guard let targetText = decoded.Response.TargetText, !targetText.isEmpty else {
            throw TMTError.noData
        }

        return targetText
    }

    func translateBatch(
        _ texts: [String],
        onProgress: @escaping (Int) -> Void
    ) async throws -> [String] {
        var results: [String] = []
        results.reserveCapacity(texts.count)

        for (index, text) in texts.enumerated() {
            let translated = try await translate(text)
            results.append(translated)
            onProgress(index)

            if index < texts.count - 1 {
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        return results
    }

    // MARK: - HMAC

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let code = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(code)
    }

    private func hexString(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
