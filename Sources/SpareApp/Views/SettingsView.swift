import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tool: SettingsModel

    init(model: AppModel) {
        self.model = model
        tool = model.settingsScreen
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Settings", subtitle: "Everything stays on your Mac. No account, no internet.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ToolList {
                        settingRow("Warn when free space is below") {
                            valueStepper("\(String(model.settings.diskAlertThresholdGB)) GB",
                                         value: $model.settings.diskAlertThresholdGB, range: 5...500, step: 5)
                        }
                        divider
                        settingRow("Warn when memory is high") {
                            Toggle("", isOn: $model.settings.memoryAlertsEnabled)
                                .toggleStyle(.switch).labelsHidden().tint(Ink.spare)
                        }
                        divider
                        settingRow("Idle project after") {
                            valueStepper("\(String(model.settings.projectIdleDays)) days",
                                         value: $model.settings.projectIdleDays, range: 7...365, step: 7)
                        }
                        divider
                        settingRow("Open Spare at login") {
                            Toggle("", isOn: Binding(get: { tool.opensAtLogin }, set: { tool.setOpensAtLogin($0) }))
                                .toggleStyle(.switch).labelsHidden().tint(Ink.spare)
                        }
                        if tool.loginFailed {
                            Text("macOS did not allow this now. It usually works once Spare is installed in Applications.")
                                .font(Txt.caption).foregroundStyle(Ink.review)
                                .padding(.horizontal, 16).padding(.bottom, 12)
                        }
                    }
                    projects
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .onAppear { tool.refresh() }
    }

    // MARK: Project folders

    private var projects: some View {
        ToolList {
            HStack {
                Text("Project folders").font(Txt.body)
                Spacer()
                Button("Add folder") { addFolder() }.buttonStyle(QuietButton())
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            ForEach(model.settings.projectRootPaths, id: \.self) { path in
                divider
                HStack {
                    Text(verbatim: path).font(Txt.path).foregroundStyle(Ink.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { model.settings.projectRootPaths.removeAll { $0 == path } } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Ink.tertiary).frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Remove folder")
                    .accessibilityLabel(Text("Remove folder"))
                }
                .padding(.horizontal, 16)
                .frame(height: 40)
            }
            if model.settings.projectRootPaths.isEmpty {
                divider
                Text("No folder. Idle project leftovers will not be found.")
                    .font(Txt.caption).foregroundStyle(Ink.tertiary)
                    .padding(.horizontal, 16).frame(height: 40, alignment: .leading)
            }
        }
    }

    // MARK: Pieces

    private var divider: some View {
        Rectangle().fill(Ink.line).frame(height: 1)
    }

    private func settingRow<Control: View>(_ title: LocalizedStringKey, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).font(Txt.body)
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func valueStepper(_ text: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        HStack(spacing: 10) {
            Text(text).font(Txt.label).foregroundStyle(Ink.secondary).monospacedDigit()
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = model.home
        if panel.runModal() == .OK, let url = panel.url, !model.settings.projectRootPaths.contains(url.path) {
            model.settings.projectRootPaths.append(url.path)
        }
    }
}
