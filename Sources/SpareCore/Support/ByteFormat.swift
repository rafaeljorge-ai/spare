import Foundation

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func gigabytes(_ bytes: Int64) -> Int {
        Int((Double(bytes) / 1_000_000_000).rounded())
    }
}
