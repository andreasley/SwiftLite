import Foundation

public extension UUID
{
    /// Creates a UUIDv7 with millisecond timestamp + random bytes (RFC 9562).
    static func v7() -> UUID
    {
        var bytes = (UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                     UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                     UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                     UInt8(0), UInt8(0), UInt8(0), UInt8(0))

        // 48-bit unix timestamp in milliseconds (big-endian)
        let ms = UInt64(Date().timeIntervalSince1970 * 1000)
        withUnsafeBytes(of: ms.bigEndian) { src in
            withUnsafeMutableBytes(of: &bytes) { dst in
                // Copy lower 6 bytes of the 8-byte big-endian UInt64
                dst[0] = src[2]
                dst[1] = src[3]
                dst[2] = src[4]
                dst[3] = src[5]
                dst[4] = src[6]
                dst[5] = src[7]
            }
        }

        // Fill bytes 6–15 with random data
        withUnsafeMutableBytes(of: &bytes) { dst in
            for i in 6..<16 {
                dst[i] = UInt8.random(in: .min ... .max)
            }
        }

        // Set version (0b0111) in bits 48–51
        withUnsafeMutableBytes(of: &bytes) { dst in
            dst[6] = (dst[6] & 0x0F) | 0x70
        }

        // Set variant (0b10) in bits 64–65
        withUnsafeMutableBytes(of: &bytes) { dst in
            dst[8] = (dst[8] & 0x3F) | 0x80
        }

        return UUID(uuid: bytes)
    }
}

public extension UUID
{
    static let max = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
