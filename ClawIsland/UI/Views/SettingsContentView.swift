import SwiftUI

struct SettingsContentView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var claudeConfigOK = false
    @State private var codexConfigOK = false

    var body: some View {
        VStack(spacing: 16) {
            displaySection
            configSection
            versionSection
            Spacer(minLength: 0)
            quitButton
        }
        .padding(16)
        .onAppear { refreshConfigStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidShow)) { _ in refreshConfigStatus() }
    }

    // MARK: - Config section

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Config")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            settingsGroup {
                configRow(label: "Claude Code", isOK: claudeConfigOK) {
                    fixClaudeConfig()
                }
                configRow(label: "Codex", isOK: codexConfigOK) {
                    fixCodexConfig()
                }
            }
        }
    }

    private func configRow(label: String, isOK: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(isOK ? Color.green.opacity(0.8) : Color.red.opacity(0.7))
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Button {
                action()
            } label: {
                Text(isOK ? "Ready" : "Fix")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isOK ? Color.green.opacity(0.7) : Color.red.opacity(0.75))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isOK)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func fixClaudeConfig() {
        if let bridgeSource = Bundle.main.path(forResource: "ClawBridge", ofType: nil),
           FileManager.default.isExecutableFile(atPath: bridgeSource) {
            try? HookInstaller.install(bridgeSourcePath: bridgeSource)
        }
        refreshConfigStatus()
    }

    private func fixCodexConfig() {
        if let codexSource = Bundle.main.path(forResource: "CodexBridge", ofType: nil),
           FileManager.default.isExecutableFile(atPath: codexSource) {
            try? HookInstaller.installCodex(bridgeSourcePath: codexSource)
        }
        refreshConfigStatus()
    }

    private func refreshConfigStatus() {
        claudeConfigOK = HookInstaller.validateHooks()
        codexConfigOK = HookInstaller.validateCodexHooks()
    }

    // MARK: - Display section

    private var displaySection: some View {
        settingsGroup {
            settingsRow(icon: "display", label: "Display on") {
                screenPicker
            }
        }
    }

    // MARK: - Version section

    private var versionSection: some View {
        settingsGroup {
            settingsRow(icon: "info.circle", label: "Version") {
                aboutVersion
            }
        }
    }

    // MARK: - Quit button

    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit Island")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.red.opacity(0.8))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Screen picker

    private var screenPicker: some View {
        Menu {
            Button("Auto") { settings.preferredScreenName = nil }
            Divider()
            ForEach(availableScreens, id: \.name) { screen in
                Button(screen.name) { settings.preferredScreenName = screen.name }
            }
        } label: {
            Text(settings.preferredScreenName ?? "Auto")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var availableScreens: [ScreenInfo] {
        NSScreen.screens.map {
            ScreenInfo(name: $0.localizedName, width: $0.frame.width, height: $0.frame.height)
        }
    }

    // MARK: - About

    private var aboutVersion: some View {
        Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    // MARK: - Layout helpers

    private func settingsGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func settingsRow<Content: View>(
        icon: String,
        label: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Data

private struct ScreenInfo {
    let name: String
    let width: CGFloat
    let height: CGFloat
}
