import Foundation

public enum OctalUnescape {
    /// tmux control mode `%output` payload 를 디코딩.
    /// `\ooo` (3자리 8진수) 를 해당 바이트로 치환. 형식 불량이면 그대로 둠.
    public static func decode(_ input: String) -> Data {
        var output = Data()
        output.reserveCapacity(input.utf8.count)

        let bytes = Array(input.utf8)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x5C /* backslash */,
               i + 3 < bytes.count,
               let d1 = octalDigit(bytes[i + 1]),
               let d2 = octalDigit(bytes[i + 2]),
               let d3 = octalDigit(bytes[i + 3])
            {
                let value = UInt8(d1 * 64 + d2 * 8 + d3)
                output.append(value)
                i += 4
            } else {
                output.append(b)
                i += 1
            }
        }
        return output
    }

    private static func octalDigit(_ b: UInt8) -> Int? {
        guard b >= 0x30, b <= 0x37 else { return nil }
        return Int(b - 0x30)
    }
}
