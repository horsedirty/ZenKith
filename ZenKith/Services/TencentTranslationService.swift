import Foundation
import CommonCrypto

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
        Self.runSelfTest()
    }

    func translate(_ text: String) async throws -> String {
        guard !secretId.isEmpty, !secretKey.isEmpty else {
            throw TMTError.invalidCredentials
        }

        let service = "tmt"
        let host = "tmt.tencentcloudapi.com"
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
        let payloadHash = sha256Hex(payloadData)

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

        // Step 1: Canonical Request
        let httpMethod = "POST"
        let canonicalURI = "/"
        let canonicalQueryString = ""
        let canonicalHeaders = "content-type:application/json\n"
        let signedHeaders = "content-type"

        let canonicalRequest = httpMethod + "\n"
            + canonicalURI + "\n"
            + canonicalQueryString + "\n"
            + canonicalHeaders + "\n"
            + signedHeaders + "\n"
            + payloadHash

        let hashedCanonicalRequest = sha256Hex(Data(canonicalRequest.utf8))

        // Step 2: String to Sign
        let credentialScope = "\(dateStamp)/\(service)/tc3_request"
        let stringToSign = algorithm + "\n"
            + timestampStr + "\n"
            + credentialScope + "\n"
            + hashedCanonicalRequest

        // Step 3: Signing key derivation
        let kDate    = hmacSHA256(key: "TC3\(secretKey)", data: dateStamp)
        let kService = hmacSHA256(key: kDate, data: service)
        let kSigning = hmacSHA256(key: kService, data: "tc3_request")

        // Step 4: Signature
        let signature = hmacSHA256Hex(key: kSigning, data: stringToSign)

        // Step 5: Authorization
        let auth = "\(algorithm) Credential=\(secretId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        // Build request
        var req = URLRequest(url: URL(string: "https://\(host)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(action, forHTTPHeaderField: "X-TC-Action")
        req.setValue(String(unixTimestamp), forHTTPHeaderField: "X-TC-Timestamp")
        req.setValue(version, forHTTPHeaderField: "X-TC-Version")
        req.setValue("ap-guangzhou", forHTTPHeaderField: "X-TC-Region")
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        req.httpBody = payloadData

        let (data, resp) = try await session.data(for: req)
        let body = String(data: data, encoding: .utf8) ?? ""

        guard let httpResp = resp as? HTTPURLResponse else {
            throw TMTError.requestFailed("无效响应")
        }

        if httpResp.statusCode != 200 {
            if let err = try? JSONDecoder().decode(TMTResponse.self, from: data),
               let msg = err.Response.Error?.Message {
                throw TMTError.apiError(msg)
            }
            throw TMTError.requestFailed("HTTP \(httpResp.statusCode): \(body)")
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
            SecretId: \(secretId.prefix(8))...
            SecretKey len: \(secretKey.count)
            ---
            HTTP Headers:
            \(req.allHTTPHeaderFields?.map { "\($0): \($1)" }.joined(separator: "\n") ?? "none")
            Body: \(String(data: payloadData, encoding: .utf8) ?? "?")
            """
            throw TMTError.requestFailed("\(apiError.Message)\n\(debugInfo)")
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
            let t = try await translate(text)
            results.append(t)
            onProgress(index)
            if index < texts.count - 1 {
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return results
    }

    // MARK: - Crypto (CommonCrypto)

    private func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: String, data: String) -> Data {
        let keyData = Data(key.utf8)
        let dataBytes = Data(data.utf8)
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { kPtr in
            dataBytes.withUnsafeBytes { dPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       kPtr.baseAddress, keyData.count,
                       dPtr.baseAddress, dataBytes.count,
                       &result)
            }
        }
        return Data(result)
    }

    private func hmacSHA256(key: Data, data: String) -> Data {
        let dataBytes = Data(data.utf8)
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { kPtr in
            dataBytes.withUnsafeBytes { dPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       kPtr.baseAddress, key.count,
                       dPtr.baseAddress, dataBytes.count,
                       &result)
            }
        }
        return Data(result)
    }

    private func hmacSHA256Hex(key: Data, data: String) -> String {
        let hmacData = hmacSHA256(key: key, data: data)
        return hmacData.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Self Test (verifies HMAC/SHA256 against Tencent official test vector)

    private static func runSelfTest() {
        let testSecretKey = "Gu5t9xGARNpq86cd98joQYCN3EXAMPLE"

        func sha256Hex(_ d: Data) -> String {
            var h = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            d.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(d.count), &h) }
            return h.map { String(format: "%02x", $0) }.joined()
        }
        func hmacRaw(key: Data, msg: Data) -> Data {
            var r = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            key.withUnsafeBytes { kPtr in
                msg.withUnsafeBytes { mPtr in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                           kPtr.baseAddress, key.count, mPtr.baseAddress, msg.count, &r)
                }
            }
            return Data(r)
        }

        let payload = "{\"Limit\": 1, \"Filters\": [{\"Values\": [\"\\u672a\\u547d\\u540d\"], \"Name\": \"instance-name\"}]}"
        let payloadHash = sha256Hex(Data(payload.utf8))

        let canonicalReq = "POST\n/\n\ncontent-type:application/json\nhost:cvm.tencentcloudapi.com\n\ncontent-type;host\n\(payloadHash)"
        let hashedCR = sha256Hex(Data(canonicalReq.utf8))

        let sts = "TC3-HMAC-SHA256\n1551113065\n2019-02-25/cvm/tc3_request\n\(hashedCR)"

        let kDate  = hmacRaw(key: Data("TC3\(testSecretKey)".utf8), msg: Data("2019-02-25".utf8))
        let kSvc   = hmacRaw(key: kDate, msg: Data("cvm".utf8))
        let kSign  = hmacRaw(key: kSvc, msg: Data("tc3_request".utf8))
        let sig    = hmacRaw(key: kSign, msg: Data(sts.utf8)).map { String(format: "%02x", $0) }.joined()

        print("[TC3 SelfTest] payloadHash: \(payloadHash)")
        print("[TC3 SelfTest] hashedCR:   \(hashedCR)")
        print("[TC3 SelfTest] expected:   5ffe6a04c0664f34a8d476903fbe9a1a0ce595fc52823022bedfa1990de01e19")
        print("[TC3 SelfTest] crMatch:    \(hashedCR == "5ffe6a04c0664f34a8d476903fbe9a1a0ce595fc52823022bedfa1990de01e19")")
        print("[TC3 SelfTest] signature:  \(sig)")
    }
}
