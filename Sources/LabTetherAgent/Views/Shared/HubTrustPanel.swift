import AppKit
import SwiftUI

/// "This Hub uses its own certificate": the fingerprint to compare with the
/// console, and the choice. Shown in setup and in Settings › Connection.
struct HubTrustPanel: View {
    let offer: HubCAOffer
    let isWorking: Bool
    let onTrust: () -> Void
    let onCancel: () -> Void

    @State private var copied = false

    var body: some View {
        LTSheet(padding: EdgeInsets(top: LT.space12, leading: LT.space16, bottom: LT.space12, trailing: LT.space16)) {
            VStack(alignment: .leading, spacing: LT.space8) {
                Text(offer.replacesSavedCA ? "This Hub's certificate changed" : "This Hub uses its own certificate")
                    .font(LT.font(13, weight: .semibold))
                    .foregroundStyle(LT.text)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .top, spacing: LT.space12) {
                    Text("Fingerprint")
                        .font(LT.font(12))
                        .foregroundStyle(LT.text3)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(offer.groupedRows, id: \.self) { row in
                            Text(row)
                                .font(LT.mono(12))
                                .foregroundStyle(LT.text)
                        }
                    }
                    .textSelection(.enabled)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Fingerprint")
                    .accessibilityValue(offer.groupedRows.joined(separator: " "))
                    .accessibilityIdentifier("hub-trust-fingerprint")
                    Spacer(minLength: LT.space8)
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(offer.fingerprint, forType: .string)
                        copied = true
                    }
                    .buttonStyle(LTTextButtonStyle(fontSize: 12))
                    .accessibilityLabel("Copy fingerprint")
                }
                Text("Compare it with the fingerprint in the console under Add device.")
                    .font(LT.font(12))
                    .foregroundStyle(LT.text2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: LT.space8) {
                    Spacer()
                    if isWorking { LTSpinnerArc(color: LT.text3, size: 12) }
                    Button("Cancel", action: onCancel)
                        .buttonStyle(LTSecondaryButtonStyle())
                    Button("Trust this Hub", action: onTrust)
                        .buttonStyle(LTPrimaryButtonStyle())
                        .accessibilityIdentifier("hub-trust-accept")
                }
                .disabled(isWorking)
            }
        }
    }
}
