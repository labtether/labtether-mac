import Foundation

/// Reassembles newline-delimited log lines from arbitrary pipe read chunks.
///
/// `FileHandle.availableData` does not guarantee chunk boundaries align with
/// line endings, so we keep any trailing fragment until the next read. Oversized
/// lines are emitted as bounded continuations without splitting UTF-8 scalars.
final class LogPipeChunkDecoder {
    static let maximumPendingBytes = 64 * 1024

    struct Line: Equatable, Sendable {
        let text: String
        /// Every fragment of an oversized line, including the first one.
        let isContinuation: Bool
    }

    private var pending = Data()
    private var isContinuation = false

    func ingest(_ data: Data) -> [Line] {
        guard !data.isEmpty else { return [] }
        var lines: [Line] = []
        var lineStart = data.startIndex
        var index = data.startIndex

        // Scan only the new read; retained bytes have no line separators.
        while index < data.endIndex {
            let byte = data[index]
            if byte == 0x0A || byte == 0x0D {
                append(data, range: lineStart..<index, into: &lines)
                if !pending.isEmpty {
                    lines.append(Line(text: decodeLine(pending), isContinuation: isContinuation))
                }
                pending = Data()
                isContinuation = false
                lineStart = data.index(after: index)
            }
            index = data.index(after: index)
        }
        append(data, range: lineStart..<data.endIndex, into: &lines)
        return lines
    }

    func finish() -> [Line] {
        defer {
            pending = Data()
            isContinuation = false
        }
        let decoded = decodeLine(pending[...])
        let trailing = isContinuation ? decoded : decoded.trimmingCharacters(in: .newlines)
        return trailing.isEmpty ? [] : [Line(text: trailing, isContinuation: isContinuation)]
    }

    private func append(_ data: Data, range: Range<Data.Index>, into lines: inout [Line]) {
        var position = range.lowerBound
        while position < range.upperBound {
            if pending.count == Self.maximumPendingBytes {
                let end = completeUTF8PrefixEnd()
                lines.append(Line(text: decodeLine(pending[..<end]), isContinuation: true))
                pending = Data(pending[end...])
                isContinuation = true
            }
            let count = min(Self.maximumPendingBytes - pending.count,
                            data.distance(from: position, to: range.upperBound))
            let end = data.index(position, offsetBy: count)
            pending.append(data[position..<end])
            position = end
        }
    }

    /// Keep a partial UTF-8 scalar with the next fragment (at most three bytes).
    private func completeUTF8PrefixEnd() -> Data.Index {
        var lead = pending.index(before: pending.endIndex)
        var trailingBytes = 0
        while trailingBytes < 3 && lead > pending.startIndex && pending[lead] & 0xC0 == 0x80 {
            trailingBytes += 1
            lead = pending.index(before: lead)
        }
        let byte = pending[lead]
        let expectedLength: Int
        switch byte {
        case 0xC2...0xDF: expectedLength = 2
        case 0xE0...0xEF: expectedLength = 3
        case 0xF0...0xF4: expectedLength = 4
        default: expectedLength = 1
        }
        return trailingBytes + 1 < expectedLength ? lead : pending.endIndex
    }

    private func decodeLine<T: DataProtocol>(_ bytes: T) -> String {
        let data = Data(bytes)
        if let line = String(data: data, encoding: .utf8) {
            return line
        }
        return String(decoding: data, as: UTF8.self)
    }
}
