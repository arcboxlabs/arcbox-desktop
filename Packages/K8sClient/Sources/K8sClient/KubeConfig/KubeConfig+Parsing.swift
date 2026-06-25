import Foundation

extension KubeConfig {
    // MARK: - Private

    /// Extract the first value for a given YAML key from the raw string.
    /// Handles both `key: value` and `key: "value"` forms.
    static func extractValue(for key: String, from yaml: String) -> String? {
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            var value = String(trimmed.dropFirst(key.count))
                .trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes if present
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Convert PEM-encoded data to DER by stripping headers and decoding inner base64.
    /// If the data is already DER (no PEM headers), returns it as-is.
    static func pemToDER(_ data: Data) -> Data {
        guard let pem = String(data: data, encoding: .utf8),
            pem.contains("-----BEGIN")
        else {
            return data
        }
        let base64 =
            pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: base64) ?? data
    }

}
