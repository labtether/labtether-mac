import SwiftUI

/// Settings › Advanced: startup, Docker, files and logs, service discovery,
/// Remote View, menu bar, network and (collapsed) diagnostics.
struct SettingsAdvancedTab: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var status: AgentStatus
    @ObservedObject var metadata: LocalAPIMetadataStore

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space24) {
            SettingsStartupSection(settings: settings, status: status)
            dockerSection
            filesAndLogsSection
            SettingsDiscoverySection(settings: settings)
            SettingsRemoteViewSection(settings: settings)
            SettingsMenuBarSection(settings: settings)
            SettingsSection("Network") {
                SettingsNumberRow(
                    label: "Agent port",
                    text: $settings.agentPort,
                    prompt: "8091",
                    range: 1...65535,
                    onChange: { settings.markChanged() }
                )
            }
            SettingsDiagnosticsSection(settings: settings, status: status, metadata: metadata)
        }
    }

    // MARK: - Docker

    private var dockerSection: some View {
        SettingsSection("Docker") {
            SettingsPickerRow(
                label: "Docker",
                selection: Binding(
                    get: { settings.normalizedDockerMode() },
                    set: { settings.dockerEnabled = $0; settings.markChanged() }
                ),
                options: [("Auto", "auto"), ("On", "true"), ("Off", "false")]
            )
            if settings.normalizedDockerMode() != "false" {
                Text("Gives the Hub control of Docker on this Mac.")
                    .font(LT.font(12))
                    .foregroundStyle(LT.warnText)
                    .padding(.leading, 140)
                    .padding(.bottom, LT.space4)
                SettingsTextRow(
                    label: "Docker endpoint",
                    text: $settings.dockerEndpoint,
                    prompt: "/var/run/docker.sock",
                    onChange: { settings.markChanged() }
                )
                SettingsNumberRow(
                    label: "Discovery interval (s)",
                    text: $settings.dockerDiscoveryIntervalSec,
                    prompt: "30",
                    range: 5...3600,
                    onChange: { settings.markChanged() }
                )
            }
        }
    }

    // MARK: - Files and logs

    private var filesAndLogsSection: some View {
        SettingsSection("Files and logs") {
            SettingsPickerRow(
                label: "File access",
                selection: Binding(
                    get: { settings.normalizedFilesRootMode() },
                    set: { settings.filesRootMode = $0; settings.markChanged() }
                ),
                options: [("Home folder", "home"), ("Whole disk", "full")]
            )
            LTToggleRow(
                label: "Allow Hub overrides",
                isOn: $settings.allowRemoteOverrides,
                detail: "The Hub can change these settings.",
                onChange: { settings.markChanged() }
            )
            SettingsPickerRow(
                label: "Log level",
                selection: Binding(
                    get: { settings.normalizedLogLevel() },
                    set: { settings.logLevel = $0; settings.markChanged() }
                ),
                options: [("Debug", "debug"), ("Info", "info"), ("Warn", "warn"), ("Error", "error")]
            )
        }
    }
}

/// Which services the agent looks for and reports to the Hub.
struct SettingsDiscoverySection: View {
    @ObservedObject var settings: AgentSettings

    var body: some View {
        SettingsSection("Service discovery") {
            toggle("Docker services", $settings.servicesDiscoveryDockerEnabled)
            toggle("Proxy services", $settings.servicesDiscoveryProxyEnabled)
            if settings.servicesDiscoveryProxyEnabled {
                toggle("Traefik", $settings.servicesDiscoveryProxyTraefikEnabled)
                toggle("Caddy", $settings.servicesDiscoveryProxyCaddyEnabled)
                toggle("Nginx Proxy Manager", $settings.servicesDiscoveryProxyNPMEnabled)
            }
            toggle("Local port scan", $settings.servicesDiscoveryPortScanEnabled)
            if settings.servicesDiscoveryPortScanEnabled {
                toggle("Listening sockets", $settings.servicesDiscoveryPortScanIncludeListening)
                SettingsTextRow(
                    label: "Ports",
                    text: $settings.servicesDiscoveryPortScanPorts,
                    prompt: "80,443,3000",
                    onChange: { settings.markChanged() }
                )
            }
            LTToggleRow(
                label: "LAN scan",
                isOn: $settings.servicesDiscoveryLANScanEnabled,
                detail: settings.servicesDiscoveryLANScanEnabled
                    ? "Probes every address in these ranges on the listed ports."
                    : nil,
                onChange: { settings.markChanged() }
            )
            if settings.servicesDiscoveryLANScanEnabled {
                SettingsTextRow(
                    label: "Ranges (CIDR)",
                    text: $settings.servicesDiscoveryLANScanCIDRs,
                    prompt: "192.0.2.0/24",
                    onChange: { settings.markChanged() }
                )
                SettingsTextRow(
                    label: "Ports",
                    text: $settings.servicesDiscoveryLANScanPorts,
                    prompt: "80,443",
                    onChange: { settings.markChanged() }
                )
                SettingsNumberRow(
                    label: "Host limit",
                    text: $settings.servicesDiscoveryLANScanMaxHosts,
                    prompt: "64",
                    range: 1...1024,
                    onChange: { settings.markChanged() }
                )
            }
        }
    }

    private func toggle(_ label: String, _ isOn: Binding<Bool>) -> some View {
        LTToggleRow(label: label, isOn: isOn, onChange: { settings.markChanged() })
    }
}
