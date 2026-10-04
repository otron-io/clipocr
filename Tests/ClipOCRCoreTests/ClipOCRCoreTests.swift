import AppKit
import ClipOCRCore
import XCTest

final class ClipOCRCoreTests: XCTestCase {
    private func workspace() throws -> RequestWorkspace {
        let root = ProcessInfo.processInfo.environment["CLIPOCR_TEST_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? RequestWorkspace.defaultRoot.appendingPathComponent("tests", isDirectory: true)
        return try RequestWorkspace(root: root)
    }

    func testSingleLineIsVerbatim() {
        let text = "  Café — file_name.swift:42  "
        XCTAssertEqual(TextRecognizer.arrange([
            RecognizedLine(text: text, bounds: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.1))
        ]), text)
    }

    func testTopToBottomReadingOrder() {
        let lines = [
            RecognizedLine(text: "Second line", bounds: CGRect(x: 0.1, y: 0.5, width: 0.55, height: 0.1)),
            RecognizedLine(text: "First line!", bounds: CGRect(x: 0.1, y: 0.7, width: 0.55, height: 0.1))
        ]
        XCTAssertEqual(TextRecognizer.arrange(lines), "First line!\nSecond line")
    }

    func testFragmentsOnOneRowStayOnOneLine() {
        let lines = [
            RecognizedLine(text: "world", bounds: CGRect(x: 0.4, y: 0.7, width: 0.25, height: 0.1)),
            RecognizedLine(text: "Hello", bounds: CGRect(x: 0.1, y: 0.71, width: 0.25, height: 0.1))
        ]
        XCTAssertEqual(TextRecognizer.arrange(lines), "Hello world")
    }

    func testCodeIndentationIsRecoveredFromGeometry() {
        let lines = [
            RecognizedLine(text: "if true {", bounds: CGRect(x: 0.1, y: 0.7, width: 0.45, height: 0.08)),
            RecognizedLine(text: "return 42", bounds: CGRect(x: 0.3, y: 0.57, width: 0.45, height: 0.08)),
            RecognizedLine(text: "}", bounds: CGRect(x: 0.1, y: 0.44, width: 0.05, height: 0.08))
        ]
        XCTAssertEqual(TextRecognizer.arrange(lines), "if true {\n    return 42\n}")
    }

    func testLargeParagraphGapAddsBlankLine() {
        let lines = [
            RecognizedLine(text: "First", bounds: CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.1)),
            RecognizedLine(text: "Next", bounds: CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.1))
        ]
        XCTAssertEqual(TextRecognizer.arrange(lines), "First\n\nNext")
    }

    func testEmptyAndInvalidObservationsAreIgnored() {
        XCTAssertEqual(TextRecognizer.arrange([
            RecognizedLine(text: "  ", bounds: CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.1)),
            RecognizedLine(text: "hidden", bounds: .zero),
            RecognizedLine(text: "invalid", bounds: .infinite)
        ]), "")
    }

    func testWorkspaceIsPrivateAndCleanedUp() throws {
        let request = try workspace()
        let directory = request.directory
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        try Data("private screenshot".utf8).write(to: request.image)
        request.cleanUp()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testWorkspaceDeinitCleansUp() throws {
        var request: RequestWorkspace? = try workspace()
        let directory = request!.directory
        request = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testStaleCleanupDoesNotRemoveUnrelatedFiles() throws {
        let request = try workspace()
        defer { request.cleanUp() }
        let stale = request.directory.appendingPathComponent("request-stale")
        let unrelated = request.directory.appendingPathComponent("keep-me")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: unrelated)
        RequestWorkspace.cleanStaleRequests(root: request.directory, olderThan: -1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testProcessOutputAndExitStatus() async throws {
        let request = try workspace()
        defer { request.cleanUp() }
        let result = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'output'; printf 'error' >&2; exit 7"],
            directory: request.directory
        )
        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(result.stdout, "output")
        XCTAssertEqual(result.stderr, "error")
    }

    func testProcessDoesNotDeadlockOnLargeOutput() async throws {
        let request = try workspace()
        defer { request.cleanUp() }
        let result = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: [String(repeating: "x", count: 100_000)], directory: request.directory
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.utf8.count, 65_536)
        XCTAssertTrue(result.stdout.hasSuffix("\n"))
    }

    func testProcessTimeout() async throws {
        let request = try workspace()
        defer { request.cleanUp() }
        do {
            _ = try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"],
                directory: request.directory, timeout: 0.1
            )
            XCTFail("Expected timeout")
        } catch ProcessFailure.timedOut {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testProcessCancellation() async throws {
        let request = try workspace()
        defer { request.cleanUp() }
        let task = Task {
            try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"],
                directory: request.directory
            )
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testFailedProcessLaunchCleansLogs() async throws {
        let request = try workspace()
        defer { request.cleanUp() }
        do {
            _ = try await ProcessRunner().run(
                executable: request.directory.appendingPathComponent("does-not-exist"), arguments: [],
                directory: request.directory
            )
            XCTFail("Expected launch failure")
        } catch {
            // The continuation resumes before the worker's defer executes.
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: request.directory.path), [])
        }
    }

    func testInvalidImageIsRejected() async throws {
        let request = try workspace()
        defer { request.cleanUp() }
        try Data("not an image".utf8).write(to: request.image)
        do {
            _ = try await TextRecognizer().recognize(imageAt: request.image)
            XCTFail("Expected invalid image")
        } catch RecognitionFailure.invalidImage {} catch { XCTFail("Unexpected error: \(error)") }
    }

    @MainActor
    func testActualVisionRecognizesSingleLine() async throws {
        let request = try workspace()
        defer { request.cleanUp() }
        try makeImage(lines: ["ClipOCR copies text locally."], at: request.image)
        let text = try await TextRecognizer().recognize(imageAt: request.image)
        XCTAssertEqual(text, "ClipOCR copies text locally.")
    }

    @MainActor
    func testActualVisionRecognizesMultiline() async throws {
        let request = try workspace()
        defer { request.cleanUp() }
        try makeImage(lines: ["First line of text.", "Second line: 12345."], at: request.image)
        let text = try await TextRecognizer().recognize(imageAt: request.image)
        XCTAssertEqual(text, "First line of text.\nSecond line: 12345.")
    }

    @MainActor
    func testBlankImageReturnsNoText() async throws {
        let request = try workspace()
        defer { request.cleanUp() }
        try makeImage(lines: [], at: request.image)
        do {
            _ = try await TextRecognizer().recognize(imageAt: request.image)
            XCTFail("Expected no-text result")
        } catch RecognitionFailure.noText {} catch { XCTFail("Unexpected error: \(error)") }
    }

    @MainActor
    private func makeImage(lines: [String], at url: URL) throws {
        let width = 1100
        let height = 280
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 40, y: height - 90 - index * 65), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 38, weight: .regular),
                .foregroundColor: NSColor.black
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: url)
    }
}
