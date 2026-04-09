import SwiftUI

struct SettingsContentView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 16) {
            displaySection
            aboutSection
        }
        .padding(16)
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
            settingsRow(icon: "info.circle", label: "About") {
                aboutVersion
            }
        }
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
