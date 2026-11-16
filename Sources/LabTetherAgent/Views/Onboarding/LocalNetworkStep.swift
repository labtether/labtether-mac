import SwiftUI

/// The Local Network step in setup (Store edition). While macOS refuses, it
/// looks again every few seconds, so Allow in macOS's question shows here.
struct LocalNetworkStep: View {
    let hubURL: String
    /// Bumped by setup after each connection test or Connect.
    let checkToken: Int
    @State private var access: LocalNetworkAccess = .notBlocked

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space6) {
            switch access {
            case .notBlocked:
                Text(L10n.storeLocalNetworkAsk)
                    .font(LT.font(12))
                    .foregroundStyle(LT.text2)
                    .fixedSize(horizontal: false, vertical: true)
            case .denied:
                Text(L10n.storeLocalNetworkDenied(LocalNetworkAccess.appName))
                    .font(LT.font(12))
                    .foregroundStyle(LT.warnText)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.storeLocalNetworkOpenSettings, action: LocalNetworkAccess.openSettings)
                    .buttonStyle(LTSecondaryButtonStyle())
                    .accessibilityLabel("Open Local Network settings")
            }
        }
        .accessibilityIdentifier("onboarding-local-network")
        .task(id: checkToken) {
            guard checkToken > 0 else { return }
            access = await LocalNetworkAccess.probe(hubURL: hubURL)
            while access == .denied, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                access = await LocalNetworkAccess.probe(hubURL: hubURL)
            }
        }
    }
}
