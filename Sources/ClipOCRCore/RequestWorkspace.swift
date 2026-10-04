import Foundation

public final class RequestWorkspace: @unchecked Sendable {
    public let directory: URL
    public var image: URL { directory.appendingPathComponent("capture.png") }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.otron.clipocr/Requests", isDirectory: true)
    }

    public init(root: URL = RequestWorkspace.defaultRoot) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        directory = root.appendingPathComponent("request-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
    }

    public func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    deinit { cleanUp() }

    public static func cleanStaleRequests(root: URL = defaultRoot, olderThan age: TimeInterval = 3600) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey]
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("request-") {
            guard let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true,
                  let date = values.contentModificationDate,
                  date < Date().addingTimeInterval(-age) else { continue }
            try? manager.removeItem(at: entry)
        }
    }
}
