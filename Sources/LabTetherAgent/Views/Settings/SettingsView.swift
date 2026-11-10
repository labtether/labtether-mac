import SwiftUI

/// The Settings window: a segmented control over three tabs on the canvas.
/// The window title ("Settings") comes from the scene.
struct SettingsView: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var status: AgentStatus
    @ObservedObject var metadata: LocalAPIMetadataStore
    @ObservedObject var runtime: LocalAPIRuntimeStore
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings section", selection: $selectedTab) {
                Text(L10n.settingsConnection).tag(0)
                Text(L10n.settingsSecurity).tag(1)
                Text(L10n.settingsAdvanced).tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 2)
            .padding(.bottom, LT.space20)

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        switch selectedTab {
                        case 0:
                            SettingsConnectionTab(
                                settings: settings, agentProcess: agentProcess, status: status, runtime: runtime,
                                reveal: { id in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
                            )
                        case 1:
                            SettingsSecurityTab(settings: settings)
                        default:
                            SettingsAdvancedTab(settings: settings, status: status, metadata: metadata)
                        }
                    }
                    .padding(.horizontal, LT.space20)
                    .padding(.bottom, LT.space20)
                }
            }
        }
        .padding(.top, LT.space8)
        .frame(width: 560)
        .frame(minHeight: 420, idealHeight: 560)
        .background(LT.canvas)
    }
}
