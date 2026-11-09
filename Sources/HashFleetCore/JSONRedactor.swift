import Foundation

/// Shared recursive redaction for JSON request previews.
/// Keeping the sensitive-key catalog in one place prevents one tool from exposing credentials
/// that another tool already knows to hide.
public enum JSONRedactor {
    public static let sensitiveKeyFragments = [
        "password", "wifipass", "secret", "token", "authorization", "apikey", "api_key"
    ]

    public static func prettyString(from data: Data, fallback: String = "JSON request") -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let output = try? JSONSerialization.data(
                withJSONObject: redacted(object),
                options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
            )
        else {
            return fallback
        }
        return String(data: output, encoding: .utf8) ?? fallback
    }

    public static func redacted(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            return object.reduce(into: [String: Any]()) { result, pair in
                let normalizedKey = pair.key.lowercased()
                let isSensitive = sensitiveKeyFragments.contains { normalizedKey.contains($0) }
                result[pair.key] = isSensitive ? "•••••• (will be sent)" : redacted(pair.value)
            }
        }
        if let array = value as? [Any] {
            return array.map(redacted)
        }
        return value
    }
}
