import Darwin
import Foundation

public enum SizeCalculator {
    /// Inode numbers are only unique per device.
    private struct FileID: Hashable {
        let device: Int64
        let inode: UInt64
    }

    /// Bytes allocated on disk. Never follows symlinks. Hard-linked files count once.
    /// Checks for task cancellation every 1,000 files.
    public static func allocatedSize(of url: URL) -> Int64 {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return 0 }
        guard (info.st_mode & S_IFMT) == S_IFDIR else { return Int64(info.st_blocks) * 512 }

        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in true })
        else { return 0 }

        var seenInodes = Set<FileID>()
        var total: Int64 = 0
        var visited = 0
        while let child = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 1_000 == 0, Task.isCancelled { break }
            var childInfo = stat()
            guard lstat(child.path, &childInfo) == 0 else { continue }
            if (childInfo.st_mode & S_IFMT) == S_IFDIR { continue }
            if childInfo.st_nlink > 1, !seenInodes.insert(FileID(device: Int64(childInfo.st_dev), inode: UInt64(childInfo.st_ino))).inserted { continue }
            total += Int64(childInfo.st_blocks) * 512
        }
        return total
    }
}
