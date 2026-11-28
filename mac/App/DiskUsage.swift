import Foundation

/// How big a machine's disk image is, and how much space it takes on this Mac.
nonisolated struct DiskUsage: Equatable {
    /// The size Windows sees.
    let size: Int64
    /// What the file takes on the Mac's disk, which is less while the image is sparse.
    let onDisk: Int64

    /// Reads the file's sizes, or nil when it is not there. A short read of the file's
    /// attributes, so it is safe to do when a pane appears.
    static func read(path: String) -> DiskUsage? {
        let url = URL(filePath: path)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]),
              let size = values.fileSize
        else { return nil }
        return DiskUsage(size: Int64(size), onDisk: Int64(values.totalFileAllocatedSize ?? size))
    }
}
