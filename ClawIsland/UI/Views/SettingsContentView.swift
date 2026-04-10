import SwiftUI

struct SettingsContentView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var configOK = false

    var body: some View {
        VStack(spacing: 16) {
            displaySection
            aboutSection
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(16)
        .onAppear { refreshConfigStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidShow)) { _ in refreshConfigStatus() }
    }

    // MARK: - Display section

    private var displaySection: some View {
        settingsGroup {
            settingsRow(icon: "display", label: "Display on") {
                screenPicker
            }
        }
    }

    // MARK: - About section

    private var aboutSection: some View {
        settingsGroup {
            settingsRow(icon: "info.circle", label: "Version") {
                aboutVersion
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            configButton
            quitButton
        }
    }

    // MARK: - Config button

    private var configButton: some View {
        Button {
            fixConfig()
        } label: {
            Text(configOK ? "Config Ready" : "Fix Config")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(configOK ? Color.green.opacity(0.75) : Color.red.opacity(0.8))
                )
        }
        .buttonStyle(.plain)
        .disabled(configOK)
    }

    private func fixConfig() {
        guard let bridgeSource = Bundle.main.path(forResource: "ClawBridge", ofType: nil),
              FileManager.default.isExecutableFile(atPath: bridgeSource) else { return }
        try? HookInstaller.install(bridgeSourcePath: bridgeSource)
        refreshConfigStatus()
    }

    private func refreshConfigStatus() {
        configOK = HookInstaller.validateHooks()
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
