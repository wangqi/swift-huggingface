import Foundation
import RegexBuilder

extension Data {
    /// Regex pattern for data URLs
    fileprivate nonisolated(unsafe) static let dataURLRegex = Regex {
        "data:"
        Capture {
            ZeroOrMore(.reluctant) {
                CharacterClass.anyOf(",;").inverted
            }
            Optionally {
                ";charset="
            }
            Capture {
                OneOrMore(.reluctant) {
                    CharacterClass.anyOf(",;").inverted
                }
            }
        }
        Optionally { ";base64" }
        ","
        Capture {
            ZeroOrMore { .any }
        }
    }

    /// Checks if a given string is a valid data URL.
    ///
    /// - Parameter string: The string to check.
    /// - Returns: `true` if the string is a valid data URL, otherwise `false`.
    /// - SeeAlso: [RFC 2397](https://www.rfc-editor.org/rfc/rfc2397.html)
    public static func isDataURL(string: String) -> Bool {
        return string.wholeMatch(of: dataURLRegex) != nil
    }

    /// Parses a data URL string into its MIME type and data components.
    ///
    /// - Parameter string: The data URL string to parse.
    /// - Returns: A tuple containing the MIME type and decoded data, or `nil` if parsing fails.
    /// - SeeAlso: [RFC 2397](https://www.rfc-editor.org/rfc/rfc2397.html)
    public static func parseDataURL(_ string: String) -> (mimeType: String, data: Data)? {
        guard let match = string.wholeMatch(of: dataURLRegex) else {
            return nil
        }

        // Extract components using strongly typed captures
        let (_, mediatype, charset, encodedData) = match.output

        let isBase64 = string.contains(";base64,")

        // Process MIME type
        var mimeType = mediatype.isEmpty ? "text/plain" : String(mediatype)
        if !charset.isEmpty, mimeType.starts(with: "text/") {
            mimeType += ";charset=\(charset)"
        }

        // Decode data
        let decodedData: Data
        if isBase64 {
            guard let base64Data = Data(base64Encoded: String(encodedData)) else { return nil }
            decodedData = base64Data
        } else {
            guard
                let percentDecodedData = String(encodedData).removingPercentEncoding?.data(
                    using: .utf8
                )
            else { return nil }
            decodedData = percentDecodedData
        }

        return (mimeType: mimeType, data: decodedData)
    }

    /// Encodes the data as a data URL string with an optional MIME type.
    ///
    /// - Parameter mimeType: The MIME type of the data. If `nil`, "text/plain" will be used.
    /// - Returns: A data URL string representation of the data.
    /// - SeeAlso: [RFC 2397](https://www.rfc-editor.org/rfc/rfc2397.html)
    public func dataURLEncoded(mimeType: String? = nil) -> String {
        let base64Data = self.base64EncodedString()
        return "data:\(mimeType ?? "text/plain");base64,\(base64Data)"
    }

    /// Infers the image MIME type from binary magic bytes.
    /// Returns "image/jpeg", "image/png", "image/gif", or "image/webp" based on the header bytes.
    /// Falls back to nil if the format cannot be determined.
    // wangqi modified 2026-03-31
    var imageMimeType: String? {
        guard count >= 4 else { return nil }
        let bytes = [UInt8](prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if bytes.count >= 12,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return "image/webp"
        }
        return nil
    }
}
