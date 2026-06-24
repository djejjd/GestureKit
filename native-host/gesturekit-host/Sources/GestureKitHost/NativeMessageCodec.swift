import Foundation

public enum NativeMessageCodecError: Error {
    case messageTooShort
    case lengthMismatch(expected: Int, actual: Int)
}

public enum NativeMessageCodec {
    public static func encode(_ payload: Data) -> Data {
        var length = UInt32(payload.count).littleEndian
        var output = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        output.append(payload)
        return output
    }

    public static func decode(_ input: Data) throws -> Data {
        guard input.count >= 4 else {
            throw NativeMessageCodecError.messageTooShort
        }

        let bytes = Array(input.prefix(4))
        let expectedLength =
            UInt32(bytes[0]) |
            UInt32(bytes[1]) << 8 |
            UInt32(bytes[2]) << 16 |
            UInt32(bytes[3]) << 24
        let payload = input.dropFirst(4)
        guard payload.count == Int(expectedLength) else {
            throw NativeMessageCodecError.lengthMismatch(expected: Int(expectedLength), actual: payload.count)
        }
        return Data(payload)
    }
}
