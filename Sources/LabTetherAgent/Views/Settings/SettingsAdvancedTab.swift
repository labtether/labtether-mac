import SwiftUI

struct SettingsAdvancedTab: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var status: AgentStatus
    @ObservedObject var metadata: LocalAPIMetadataStore
    @State private var diagHovered: String?

    var body: some View {
        LazyVStack(spacing: LT.space12) {
            SettingsCardSection("STARTUP") {
                SettingsToggleRow(icon: "person.badge.clock.fill", label: "Start at Login",
                                  isOn: Binding(
                                      get: { settings.startAtLogin },
                                      set: { newValue in
                                          if LoginItemManager.setEnabled(newValue) {
                                              settings.startAtLogin = newValue
                                          } else {
                                              status.markError("Start at Login requires running as an installed .app bundle.")
                                          }
                                      }
                                  ))

                SettingsToggleRow(icon: "play.circle.fill", label: "Auto-Start Agent on Launch",
                                  isOn: $settings.autoStart)

                SettingsToggleRow(icon: "arrow.triangle.2.circlepath.circle.fill", label: "Auto-Update Agent on Startup",
                                  isOn: $settings.autoUpdateEnabled,
                                  onChange: { settings.markChanged() })
            }

            SettingsCardSection("DOCKER INTEGRATION") {
                HStack(spacing: LT.space8) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LT.textMuted)
                        .frame(width: 16)
                    Text("Docker Mode")
                        .font(LT.inter(12, weight: .medium))
                        .foregroundStyle(LT.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { normalizedDockerMode },
                        set: { newValue in
                            settings.dockerEnabled = newValue
                            settings.markChanged()
                        }
                    )) {
                        Text("Auto").tag("auto")
                        Text("Enabled").tag("true")
                        Text("Disabled").tag("false")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                .padding(.horizontal, LT.space12)
                .padding(.vertical, LT.space4)
                .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                        .strokeBorder(LT.panelBorder, lineWidth: 1)
                )

                if normalizedDockerMode != "false" {
                    SettingsIconField(icon: "link", label: "Docker Endpoint",
                                      text: $settings.dockerEndpoint,
                                      prompt: "/var/run/docker.sock or unix:///var/run/docker.sock",
                                      onChange: { settings.markChanged() })

                    SettingsIconField(icon: "clock.fill", label: "Discovery Interval (sec)",
                                      text: $settings.dockerDiscoveryIntervalSec,
                                      prompt: "30",
                                      onChange: {
                                          let filtered = settings.dockerDiscoveryIntervalSec.filter { $0.isNumber }
                                          if filtered != settings.dockerDiscoveryIntervalSec {
                                              settings.dockerDiscoveryIntervalSec = filtered
                                          }
                                          if let interval = Int(filtered), interval > 3600 {
                                              settings.dockerDiscoveryIntervalSec = "3600"
                                          } else if let interval = Int(filtered), interval < 5 && !filtered.isEmpty {
                                              settings.dockerDiscoveryIntervalSec = "5"
                                          }
                                          settings.markChanged()
                                      })

                    HStack(spacing: LT.space8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(LT.warn)
                        Text("Docker mode grants broad host control. Enable only on trusted hosts.")
                            .font(LT.inter(10, weight: .medium))
                            .foregroundStyle(LT.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, LT.space4)
                }
            }

            SettingsCardSection("RUNTIME POLICY") {
                HStack(spacing: LT.space8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LT.textMuted)
                        .frame(width: 16)
                    Text("File Access Scope")
                        .font(LT.inter(12, weight: .medium))
                        .foregroundStyle(LT.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { normalizedFilesRootMode },
                        set: { newValue in
                            settings.filesRootMode = newValue
                            settings.markChanged()
                        }
                    )) {
                        Text("Home").tag("home")
                        Text("Full").tag("full")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                .padding(.horizontal, LT.space12)
                .padding(.vertical, LT.space4)
                .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                        .strokeBorder(LT.panelBorder, lineWidth: 1)
                )

                SettingsToggleRow(icon: "switch.2", label: "Allow Remote Hub Overrides",
                                  isOn: $settings.allowRemoteOverrides,
                                  onChange: { settings.markChanged() })

                HStack(spacing: LT.space8) {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LT.textMuted)
                        .frame(width: 16)
                    Text("Log Level")
                        .font(LT.inter(12, weight: .medium))
                        .foregroundStyle(LT.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { normalizedLogLevel },
                        set: { newValue in
                            settings.logLevel = newValue
                            settings.markChanged()
                        }
                    )) {
                        Text("Debug").tag("debug")
                        Text("Info").tag("info")
                        Text("Warn").tag("warn")
                        Text("Error").tag("error")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
                .padding(.horizontal, LT.space12)
                .padding(.vertical, LT.space4)
                .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                        .strokeBorder(LT.panelBorder, lineWidth: 1)
                )
            }

            SettingsCardSection("SERVICE DISCOVERY POLICY") {
                SettingsToggleRow(icon: "shippingbox.fill", label: "Discover Docker Services",
                                  isOn: $settings.servicesDiscoveryDockerEnabled,
                                  onChange: { settings.markChanged() })

                SettingsToggleRow(icon: "arrow.triangle.branch", label: "Discover Proxy Services",
                                  isOn: $settings.servicesDiscoveryProxyEnabled,
                                  onChange: { settings.markChanged() })

                if settings.servicesDiscoveryProxyEnabled {
                    SettingsToggleRow(icon: "point.3.connected.trianglepath.dotted", label: "Include Traefik",
                                      isOn: $settings.servicesDiscoveryProxyTraefikEnabled,
                                      onChange: { settings.markChanged() })
                    SettingsToggleRow(icon: "rectangle.compress.vertical", label: "Include Caddy",
                                      isOn: $settings.servicesDiscoveryProxyCaddyEnabled,
                                      onChange: { settings.markChanged() })
                    SettingsToggleRow(icon: "network", label: "Include Nginx Proxy Manager",
                                      isOn: $settings.servicesDiscoveryProxyNPMEnabled,
                                      onChange: { settings.markChanged() })
                }

                SettingsToggleRow(icon: "dot.radiowaves.left.and.right", label: "Enable Local Port Scan",
                                  isOn: $settings.servicesDiscoveryPortScanEnabled,
                                  onChange: { settings.markChanged() })

                if settings.servicesDiscoveryPortScanEnabled {
                    SettingsToggleRow(icon: "antenna.radiowaves.left.and.right", label: "Include Listening Sockets",
                                      isOn: $settings.servicesDiscoveryPortScanIncludeListening,
                                      onChange: { settings.markChanged() })
                    SettingsIconField(icon: "list.number", label: "Local Scan Ports",
                                      text: $settings.servicesDiscoveryPortScanPorts,
                                      prompt: "80,443,3000",
                                      onChange: { settings.markChanged() })
                }

                SettingsToggleRow(icon: "dot.scope", label: "Enable LAN CIDR Scan",
                                  isOn: $settings.servicesDiscoveryLANScanEnabled,
                                  onChange: { settings.markChanged() })

                if settings.servicesDiscoveryLANScanEnabled {
                    SettingsIconField(icon: "network.badge.shield.half.filled", label: "LAN CIDRs",
                                      text: $settings.servicesDiscoveryLANScanCIDRs,
                                      prompt: "192.168.1.0/24",
                                      onChange: { settings.markChanged() })
                    SettingsIconField(icon: "list.bullet.rectangle", label: "LAN Scan Ports",
                                      text: $settings.servicesDiscoveryLANScanPorts,
                                      prompt: "80,443",
                                      onChange: { settings.markChanged() })
                    SettingsIconField(icon: "number.square", label: "LAN Host Cap",
                                      text: $settings.servicesDiscoveryLANScanMaxHosts,
                                      prompt: "64",
                                      onChange: {
                                          let filtered = settings.servicesDiscoveryLANScanMaxHosts.filter { $0.isNumber }
                                          if filtered != settings.servicesDiscoveryLANScanMaxHosts {
                                              settings.servicesDiscoveryLANScanMaxHosts = filtered
                                          }
                                          if let value = Int(filtered), value > 1024 {
                                              settings.servicesDiscoveryLANScanMaxHosts = "1024"
                                          } else if let value = Int(filtered), value < 1 && !filtered.isEmpty {
                                              settings.servicesDiscoveryLANScanMaxHosts = "1"
                                          }
                                          settings.markChanged()
                                      })
                }

                HStack(spacing: LT.space8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(LT.warn)
                    Text("LAN scanning can generate noisy traffic. Keep CIDRs narrow and host cap conservative.")
                        .font(LT.inter(10, weight: .medium))
                        .foregroundStyle(LT.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, LT.space4)
            }

            SettingsCardSection("REMOTE DESKTOP / WEBRTC") {
                SettingsToggleRow(icon: "display.2", label: "Enable WebRTC Streaming",
                                  isOn: $settings.webrtcEnabled,
                                  onChange: { settings.markChanged() })

                if settings.webrtcEnabled {
                    // Screen Recording permission status
                    HStack(spacing: LT.space8) {
                        Image(systemName: ScreenRecordingPermission.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ScreenRecordingPermission.isGranted ? LT.ok : LT.warn)
                            .frame(width: 16)
                        Text("Screen Recording")
                            .font(LT.inter(12, weight: .medium))
                            .foregroundStyle(LT.textPrimary)
                        Spacer()
                        if ScreenRecordingPermission.isGranted {
                            Text("Granted")
                                .font(LT.mono(11))
                                .foregroundStyle(LT.ok)
                        } else {
                            Button("Open Settings") {
                                ScreenRecordingPermission.openSettings()
                            }
                            .buttonStyle(.plain)
                            .font(LT.inter(11, weight: .medium))
                            .foregroundStyle(LT.accent)
                        }
                    }
                    .padding(.horizontal, LT.space12)
                    .padding(.vertical, LT.space4)
                    .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                            .strokeBorder(LT.panelBorder, lineWidth: 1)
                    )
                }

                SettingsIconField(icon: "network", label: "STUN URL",
                                  text: $settings.webrtcStunURL,
                                  prompt: "stun:stun.l.google.com:19302",
                                  onChange: { settings.markChanged() })

                SettingsIconField(icon: "server.rack", label: "TURN URL",
                                  text: $settings.webrtcTurnURL,
                                  prompt: "turn:turn.example.com:3478?transport=udp",
                                  onChange: { settings.markChanged() })

                SettingsIconField(icon: "person.crop.circle", label: "TURN Username",
                                  text: $settings.webrtcTurnUser,
                                  prompt: "Optional",
                                  onChange: { settings.markChanged() })

                SettingsSecureIconField(icon: "lock.shield", label: "TURN Password",
                                        text: $settings.webrtcTurnPass,
                                        prompt: "Optional (stored in keychain)",
                                        onChange: { settings.markChanged() })

                SettingsIconField(icon: "speedometer", label: "Capture FPS",
                                  text: $settings.captureFPS,
                                  prompt: "30",
                                  onChange: {
                                      let filtered = settings.captureFPS.filter { $0.isNumber }
                                      if filtered != settings.captureFPS {
                                          settings.captureFPS = filtered
                                      }
                                      if let fps = Int(filtered), fps > 120 {
                                          settings.captureFPS = "120"
                                      } else if let fps = Int(filtered), fps < 5 && !filtered.isEmpty {
                                          settings.captureFPS = "5"
                                          }
                                          settings.markChanged()
                                  })
            }

            SettingsCardSection("MENU BAR") {
                VStack(alignment: .leading, spacing: LT.space8) {
                    HStack(spacing: LT.space8) {
                        Image(systemName: "menubar.rectangle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(LT.textMuted)
                            .frame(width: 16)
                        Text("Display Mode")
                            .font(LT.inter(12, weight: .medium))
                            .foregroundStyle(LT.textPrimary)
                        Spacer()
                    }

                    Picker("", selection: $settings.menuBarDisplayMode) {
                        Text("Compact").tag("compact")
                        Text("Standard").tag("standard")
                        Text("Verbose").tag("verbose")
                    }
                    .pickerStyle(.segmented)

                    Text(displayModeDescription)
                        .font(LT.inter(10, weight: .medium))
                        .foregroundStyle(LT.textMuted)
                }
                .padding(.horizontal, LT.space12)
                .padding(.vertical, LT.space4)
                .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                        .strokeBorder(LT.panelBorder, lineWidth: 1)
                )
            }

            SettingsCardSection("NETWORK") {
                SettingsIconField(icon: "network", label: "Agent Port",
                                  text: $settings.agentPort,
                                  prompt: "8091",
                                  onChange: {
                                      let filtered = settings.agentPort.filter { $0.isNumber }
                                      if filtered != settings.agentPort {
                                          settings.agentPort = filtered
                                      }
                                      if let port = Int(filtered), port > 65535 {
                                          settings.agentPort = "65535"
                                      } else if let port = Int(filtered), port < 1 && !filtered.isEmpty {
                                          settings.agentPort = "1"
                                      }
                                      settings.markChanged()
                                  })
            }

            SettingsCardSection("DIAGNOSTICS", glowHint: LT.accent) {
                HStack(spacing: LT.space8) {
                    LTStatusDot(color: status.state.color, size: 8)
                    Text(status.state.rawValue)
                        .font(LT.inter(12, weight: .medium))
                        .foregroundStyle(LT.textPrimary)
                    Spacer()
                }

                diagRow(icon: "internaldrive.fill", label: "Binary", value: BundleHelper.agentBinaryPath,
                        iconColor: BundleHelper.binaryExists ? LT.ok : LT.bad)
                diagRow(icon: "key.viewfinder", label: "Token File", value: settings.tokenFilePath,
                        iconColor: LT.warn)
                diagRow(icon: "doc.text.fill", label: "Settings", value: settings.agentSettingsFilePath,
                        iconColor: LT.accent)
                diagRow(icon: "lock.fill", label: "Device Key", value: settings.deviceKeyFilePath,
                        iconColor: LT.warn)
                diagRow(icon: "number.square", label: "Fingerprint", value: settings.deviceFingerprintFilePath)

                let local = metadata.snapshot
                if let fingerprint = local.deviceFingerprint, !fingerprint.isEmpty {
                    diagRow(icon: "number.square.fill", label: "Device FP", value: fingerprint)
                }
                if let bind = local.localBindAddress, !bind.isEmpty {
                    diagRow(icon: "network", label: "Local API", value: bind)
                }
                if let authEnabled = local.localAuthEnabled {
                    diagRow(icon: "shield.lefthalf.filled", label: "Local Auth", value: authEnabled ? "enabled" : "disabled")
                }
                if let insecure = local.allowInsecureTransport {
                    diagRow(icon: "exclamationmark.shield.fill", label: "Insecure WS", value: insecure ? "allowed" : "blocked")
                }

                if let pid = status.pid {
                    diagRow(icon: "number", label: "PID", value: "\(pid)")
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var normalizedDockerMode: String {
        let mode = settings.dockerEnabled.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["auto", "true", "false"].contains(mode) {
            return mode
        }
        return "auto"
    }

    private var normalizedFilesRootMode: String {
        let mode = settings.filesRootMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["home", "full"].contains(mode) {
            return mode
        }
        return "home"
    }

    private var normalizedLogLevel: String {
        let level = settings.logLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["debug", "info", "warn", "error"].contains(level) {
            return level
        }
        return "info"
    }

    private var displayModeDescription: String {
        switch settings.menuBarDisplayMode {
        case "compact": return "Shows only the status icon in the menu bar"
        case "verbose": return "Shows icon, CPU%, MEM%, and Disk% in the menu bar"
        default: return "Shows icon, CPU%, and MEM% in the menu bar"
        }
    }

    // MARK: - Diagnostics Row

    private func diagRow(icon: String, label: String, value: String, iconColor: Color = LT.textMuted) -> some View {
        HStack(spacing: LT.space8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(diagHovered == label ? iconColor : iconColor.opacity(0.7))
                .shadow(color: diagHovered == label ? iconColor.opacity(0.4) : Color.clear, radius: 3)
                .frame(width: 16)

            Text(label)
                .font(LT.mono(11))
                .foregroundStyle(diagHovered == label ? LT.textSecondary : LT.textMuted)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(LT.mono(10))
                .foregroundStyle(diagHovered == label ? LT.textPrimary : LT.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, LT.space4)
        .background(
            RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                .fill(diagHovered == label ? LT.hover : Color.clear)
        )
        .onHover { h in diagHovered = h ? label : nil }
        .animation(.easeInOut(duration: LT.animFast), value: diagHovered)
    }
}
