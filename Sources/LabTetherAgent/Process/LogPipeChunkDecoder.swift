import Foundation

/// Reassembles newline-delimited log lines from arbitrary pipe read chunks.
///
/// `FileHandle.availableData` does not guarantee chunk boundaries align with
/// line endings, so we keep any trailing fragment until the next read.
final class LogPipeChunkDecoder {
    private var pending = Data()

    func ingest(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        pending.append(data)

        var lines: [String] = []
        var lineStart = pending.startIndex
        var index = pending.startIndex

        while index < pending.endIndex {
            let byte = pending[index]
            if byte == 0x0A || byte == 0x0D {
                if lineStart != index {
                    lines.append(decodeLine(pending[lineStart..<index]))
                }
                lineStart = pending.index(after: index)
            }
            index = pending.index(after: index)
        }

        if lineStart != pending.startIndex {
            pending = lineStart < pending.endIndex ? Data(pending[lineStart...]) : Data()
        }
        return lines
    }

    func finish() -> [String] {
        defer { pending = Data() }
        let trailing = decodeLine(pending[...]).trimmingCharacters(in: .newlines)
        return trailing.isEmpty ? [] : [trailing]
    }

    private func decodeLine<T: DataProtocol>(_ bytes: T) -> String {
        let data = Data(bytes)
        if let line = String(data: data, encoding: .utf8) {
            return line
        }
        return String(decoding: data, as: UTF8.self)
    }
}
