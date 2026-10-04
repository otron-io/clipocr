import CoreGraphics
import Foundation
import ImageIO
import Vision

public enum RecognitionFailure: LocalizedError {
    case invalidImage
    case imageTooLarge
    case noText
    case recognitionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selection did not produce a readable image. Your clipboard is unchanged."
        case .imageTooLarge:
            return "The screenshot is too large. Select a smaller region (maximum 20 MB or 64 megapixels)."
        case .noText:
            return "No readable text was found. Your clipboard is unchanged."
        case .recognitionFailed:
            return "Apple Vision could not recognize this image. Try selecting a clearer region; your clipboard is unchanged."
        }
    }
}

public struct RecognizedLine: Sendable {
    public let text: String
    public let bounds: CGRect

    public init(text: String, bounds: CGRect) {
        self.text = text
        self.bounds = bounds
    }
}

private final class RecognitionControl: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRecognizeTextRequest?
    private var cancelled = false

    func register(_ request: VNRecognizeTextRequest) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.request = request
    }

    func cancel() {
        lock.lock()
        cancelled = true
        request?.cancel()
        lock.unlock()
    }

    func checkCancellation() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }
}

public struct TextRecognizer: Sendable {
    public init() {}

    public func recognize(imageAt url: URL) async throws -> String {
        let control = RecognitionControl()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try control.checkCancellation()
                        let image = try Self.loadImage(at: url)
                        let request = VNRecognizeTextRequest()
                        request.recognitionLevel = .accurate
                        // Transcribe, don't "fix" spelling, filenames, code, or identifiers.
                        request.usesLanguageCorrection = false
                        request.automaticallyDetectsLanguage = true
                        try control.register(request)
                        do {
                            try VNImageRequestHandler(cgImage: image).perform([request])
                        } catch {
                            try control.checkCancellation()
                            throw RecognitionFailure.recognitionFailed
                        }
                        try control.checkCancellation()
                        let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
                            guard let candidate = observation.topCandidates(1).first else { return nil }
                            return RecognizedLine(text: candidate.string, bounds: observation.boundingBox)
                        }
                        let text = Self.arrange(lines)
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw RecognitionFailure.noText
                        }
                        continuation.resume(returning: text)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            control.cancel()
        }
    }

    private static func loadImage(at url: URL) throws -> CGImage {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.intValue > 0 else {
            throw RecognitionFailure.invalidImage
        }
        guard size.intValue <= 20 * 1024 * 1024 else { throw RecognitionFailure.imageTooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0 else { throw RecognitionFailure.invalidImage }
        guard width.doubleValue * height.doubleValue <= 64_000_000 else {
            throw RecognitionFailure.imageTooLarge
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RecognitionFailure.invalidImage
        }
        return image
    }

    /// Reading order is top-to-bottom, then left-to-right. Vision's origin is bottom-left.
    /// Geometry recovers approximate indentation; a screenshot cannot encode tabs vs spaces.
    public static func arrange(_ input: [RecognizedLine]) -> String {
        let lines = input.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.bounds.isEmpty && !$0.bounds.isNull && !$0.bounds.isInfinite &&
            $0.bounds.minX.isFinite && $0.bounds.minY.isFinite
        }.sorted {
            if $0.bounds.midY != $1.bounds.midY { return $0.bounds.midY > $1.bounds.midY }
            return $0.bounds.minX < $1.bounds.minX
        }
        guard !lines.isEmpty else { return "" }
        let leftEdge = lines.map(\.bounds.minX).min()!
        let widths = lines.map { $0.bounds.width / CGFloat(max(1, $0.text.count)) }.sorted()
        let characterWidth = max(widths[widths.count / 2], 0.0001)
        var rows: [[RecognizedLine]] = []
        for line in lines {
            if let last = rows.last, let anchor = last.first,
               abs(anchor.bounds.midY - line.bounds.midY) <= min(anchor.bounds.height, line.bounds.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        var output: [String] = []
        var previousBottom: CGFloat?
        for row in rows {
            let ordered = row.sorted { $0.bounds.minX < $1.bounds.minX }
            let top = ordered.map(\.bounds.maxY).max()!
            let bottom = ordered.map(\.bounds.minY).min()!
            let rowHeight = max(top - bottom, 0.0001)
            if let previousBottom, previousBottom - top > rowHeight * 1.2 {
                output.append("")
            }
            var text = ""
            var rightEdge: CGFloat?
            for line in ordered {
                if let rightEdge {
                    let gap = max(0, line.bounds.minX - rightEdge)
                    let spaces = max(1, min(256, Int((gap / characterWidth).rounded())))
                    text += String(repeating: " ", count: spaces)
                } else {
                    let indentation = max(0, min(256, Int(((line.bounds.minX - leftEdge) / characterWidth).rounded())))
                    text += String(repeating: " ", count: indentation)
                }
                text += line.text
                rightEdge = line.bounds.maxX
            }
            output.append(text)
            previousBottom = bottom
        }
        return output.joined(separator: "\n")
    }
}
