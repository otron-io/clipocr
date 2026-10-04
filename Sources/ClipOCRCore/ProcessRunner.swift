import Darwin
import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public enum ProcessFailure: LocalizedError {
    case timedOut

    public var errorDescription: String? {
        "The request timed out. Your clipboard is unchanged. Please try again."
    }
}

private final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    func start(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.process = process
        try process.run()
    }

    func stop(timeout: Bool = false) {
        lock.lock()
        if timeout, process?.isRunning != true {
            lock.unlock()
            return
        }
        cancelled = true
        timedOut = timedOut || timeout
        let child = process
        if let child, child.isRunning { child.terminate() }
        lock.unlock()
        // Codex may take time to shut down. Escalate only while the same child is alive.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            lock.lock()
            defer { lock.unlock() }
            if let child = process, child.isRunning {
                Darwin.kill(child.processIdentifier, SIGKILL)
            }
        }
    }

    func finish() throws {
        lock.lock()
        defer { lock.unlock() }
        process = nil
        if timedOut { throw ProcessFailure.timedOut }
        if cancelled { throw CancellationError() }
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        directory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 90
    ) async throws -> ProcessResult {
        let control = ProcessControl()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let id = UUID().uuidString
                    let stdoutURL = directory.appendingPathComponent("\(id).stdout")
                    let stderrURL = directory.appendingPathComponent("\(id).stderr")
                    let manager = FileManager.default
                    var output: FileHandle?
                    var errors: FileHandle?
                    defer {
                        try? output?.close()
                        try? errors?.close()
                        try? manager.removeItem(at: stdoutURL)
                        try? manager.removeItem(at: stderrURL)
                    }
                    do {
                        // Files avoid pipe-buffer deadlocks with verbose CLI output.
                        guard manager.createFile(atPath: stdoutURL.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]),
                              manager.createFile(atPath: stderrURL.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]) else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        output = try FileHandle(forWritingTo: stdoutURL)
                        errors = try FileHandle(forWritingTo: stderrURL)
                        let process = Process()
                        process.executableURL = executable
                        process.arguments = arguments
                        process.currentDirectoryURL = directory
                        process.environment = environment
                        process.standardInput = FileHandle.nullDevice
                        process.standardOutput = output
                        process.standardError = errors
                        try control.start(process)
                        let timer = DispatchSource.makeTimerSource(queue: .global())
                        timer.schedule(deadline: .now() + timeout)
                        timer.setEventHandler { control.stop(timeout: true) }
                        timer.resume()
                        process.waitUntilExit()
                        timer.cancel()
                        try control.finish()
                        continuation.resume(returning: ProcessResult(
                            status: process.terminationStatus,
                            stdout: Self.readTail(stdoutURL),
                            stderr: Self.readTail(stderrURL)
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            control.stop()
        }
    }

    private static func readTail(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        do {
            let length = try handle.seekToEnd()
            try handle.seek(toOffset: length > 65_536 ? length - 65_536 : 0)
            return String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
        } catch {
            return ""
        }
    }
}
