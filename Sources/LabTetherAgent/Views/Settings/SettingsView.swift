import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var status: AgentStatus
    @ObservedObject var metadata: LocalAPIMetadataStore
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Title + tab bar
            VStack(spacing: LT.space12) {
                HStack {
                    HStack(spacing: LT.space6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(LT.accent)
                        Text("Settings")
                            .font(LT.sora(16, weight: .semibold))
                            .foregroundStyle(LT.textPrimary)
                    }
                    Spacer()
                    LTCapsuleBadge(text: "v\(BundleHelper.appVersion)", color: LT.textMuted)
                }
                tabBar
            }
            .ltScanShimmer(delay: 0.1)
            .padding(.horizontal, LT.space16)
            .padding(.top, LT.space16)
            .padding(.bottom, LT.space12)

            // Tab content
            ScrollView {
                LazyVStack(spacing: LT.space12) {
                    switch selectedTab {
                    case 0: SettingsConnectionTab(settings: settings, agentProcess: agentProcess, status: status)
                    case 1: SettingsSecurityTab(settings: settings)
                    case 2: SettingsAdvancedTab(settings: settings, status: status, metadata: metadata)
                    default: EmptyView()
                    }
                }
                .padding(.horizontal, LT.space16)
                .padding(.bottom, LT.space16)
                .id(selectedTab)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 8)),
                    removal: .opacity
                ))
            }
            .animation(LT.springSmooth, value: selectedTab)

            // Status footer
            statusFooter
        }
        .frame(width: 520)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            ZStack {
                LT.bg
                // Subtle accent glow top-center
                RadialGradient(
                    colors: [LT.accent.opacity(0.04), Color.clear],
                    center: UnitPoint(x: 0.5, y: 0.0),
                    startRadius: 0,
                    endRadius: 300
                )
            }
        )
    }

    // MARK: - Custom Pill Tab Bar

    @Namespace private var tabNamespace

    private var tabBar: some View {
        HStack(spacing: 2) {
            tabButton("Connection", icon: "bolt.fill", tag: 0)
            tabButton("Security", icon: "lock.shield.fill", tag: 1)
            tabButton("Advanced", icon: "gearshape.2.fill", tag: 2)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: LT.radiusMd, style: .continuous)
                .fill(LT.panelGlass)
                .overlay(
                    RoundedRectangle(cornerRadius: LT.radiusMd, style: .continuous)
                        .strokeBorder(LT.panelBorder, lineWidth: 0.5)
                )
        )
    }

    private func tabButton(_ label: String, icon: String, tag: Int) -> some View {
        Button {
            withAnimation(LT.springSnappy) {
                selectedTab = tag
            }
        } label: {
            HStack(spacing: LT.space4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(LT.inter(11, weight: selectedTab == tag ? .semibold : .medium))
            }
            .foregroundStyle(selectedTab == tag ? LT.accent : LT.textSecondary)
            .padding(.horizontal, LT.space12)
            .padding(.vertical, LT.space8)
            .background {
                if selectedTab == tag {
                    RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                        .fill(LT.accent.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                                .strokeBorder(LT.accent.opacity(0.2), lineWidth: 0.5)
                        )
                        .shadow(color: LT.accent.opacity(0.15), radius: 6)
                        .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Footer

    private var statusFooter: some View {
        HStack(spacing: LT.space8) {
            LTStatusDot(color: status.state.color, size: 6)
            Text(status.state.rawValue)
                .font(LT.inter(11, weight: .medium))
                .foregroundStyle(LT.textSecondary)

            Spacer()

            if let firstError = validationIssues.first {
                LTCapsuleBadge(text: firstError, color: LT.bad)
            }

            if let pid = status.pid {
                LTCapsuleBadge(text: "PID \(pid)", color: LT.textMuted)
            }
        }
        .padding(.horizontal, LT.space16)
        .padding(.vertical, 10)
        .background(LT.panelGlass)
        .overlay(alignment: .top) {
            // Specular top-edge highlight
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.white.opacity(0.05), location: 0.3),
                    .init(color: Color.white.opacity(0.05), location: 0.7),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.5)
        }
    }

    // MARK: - Helpers

    private var validationIssues: [String] {
        settings.validationErrors()
    }

    private var canStartAgent: Bool {
        settings.isConfigured && validationIssues.isEmpty && !agentProcess.isStarting
    }
}
