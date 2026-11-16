import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Security in the Store edition: the Hub CA file comes from the
/// file panel only. A typed path cannot be read in the App Sandbox, so there
/// is no text field. See `PickedHubCA.swift` for what is kept.
struct SettingsPickedCARow: View {
    @ObservedObject var settings: AgentSettings
    @State private var caError: String?
    @State private var isWorking = false

    var body: some View {
        LTFormRow(label: "CA certificate", alignment: caError == nil && settings.chosenCAProblem == nil ? .center : .top) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: LT.space8) {
                    Text(fileName)
                        .font(LT.font(13))
                        .foregroundStyle(settings.pickedCAOriginalPath.isEmpty ? LT.text3 : LT.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(settings.pickedCAOriginalPath)
                        .accessibilityLabel("CA certificate")
                        .accessibilityValue(fileName)
                    Spacer(minLength: LT.space8)
                    if isWorking { LTSpinnerArc(color: LT.text3, size: 11) }
                    Button(L10n.storeCAChoose, action: pick)
                        .buttonStyle(LTSecondaryButtonStyle())
                        .disabled(isWorking)
                    if !settings.pickedCAOriginalPath.isEmpty {
                        Button(L10n.storeCARemove, action: remove)
                            .buttonStyle(LTTextButtonStyle(fontSize: 12))
                            .accessibilityLabel("Remove CA certificate")
                            .disabled(isWorking)
                    }
                }
                if let caError {
                    LTFieldError(text: caError)
                } else if let problem = settings.chosenCAProblem {
                    HStack(alignment: .firstTextBaseline, spacing: LT.space8) {
                        LTFieldError(text: problem.words)
                        if problem == .changed {
                            Button("Check again", action: checkAgain)
                                .buttonStyle(LTTextButtonStyle(fontSize: 12))
                                .accessibilityLabel("Check CA certificate again")
                        }
                    }
                }
            }
        }
    }

    private var fileName: String {
        let path = settings.pickedCAOriginalPath
        return path.isEmpty ? L10n.storeCANone : URL(fileURLWithPath: path).lastPathComponent
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["crt", "pem", "cer"].compactMap { UTType(filenameExtension: $0) }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { await settings.choosePickedCAFile(url) }
    }

    private func remove() {
        run {
            await settings.removePickedCAFile()
            return nil
        }
    }

    /// The picked file changed or went missing: read it again through its
    /// bookmark, then check the copy against the Hub.
    private func checkAgain() {
        run {
            settings.refreshPickedCACopy()
            return await settings.chooseCAFile(settings.tlsCAFile)
        }
    }

    private func run(_ action: @escaping @MainActor () async -> String?) {
        isWorking = true
        Task { @MainActor in
            let words = await action()
            caError = words
            isWorking = false
            if words == nil { settings.markChanged() }
        }
    }
}
