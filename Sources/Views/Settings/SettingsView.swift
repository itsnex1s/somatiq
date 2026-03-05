import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(settingsService: SettingsDataService) {
        _viewModel = State(initialValue: SettingsViewModel(settingsService: settingsService))
    }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                healthSection
                aboutSection
                if let errorMessage = viewModel.errorMessage {
                    errorSection(message: errorMessage)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SomatiqColor.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .task {
                viewModel.load()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isSaving ? "Saving..." : "Save") {
                        viewModel.save()
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .tint(SomatiqColor.accent)
    }

    private var profileSection: some View {
        Section("Profile") {
            TextField("Name", text: Binding(
                get: { viewModel.name },
                set: { viewModel.name = $0 }
            ))

            Stepper("Sleep target: \(viewModel.targetSleepHours, specifier: "%.1f")h", value: Binding(
                get: { viewModel.targetSleepHours },
                set: { viewModel.targetSleepHours = $0 }
            ), in: 5 ... 10, step: 0.5)

            HStack {
                Text("Birth year")
                Spacer()
                TextField("Optional", text: birthYearTextBinding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            }
        }
    }

    private var healthSection: some View {
        Section("Health Data") {
            Button(viewModel.isAuthorizing ? "Connecting..." : "Reconnect Apple Health") {
                Task {
                    await viewModel.reconnectHealth()
                }
            }
            .disabled(viewModel.isAuthorizing)

            LabeledContent("Last sync") {
                Text(viewModel.lastSyncText)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text("1.0.0")
            }

            Link("Source Code (GitHub)", destination: URL(string: "https://github.com")!)
            Text("All health data is stored on this device only.")
                .font(.footnote)
                .foregroundStyle(SomatiqColor.textSecondary)
            Text("Somatiq provides wellness insights only and is not a medical device.")
                .font(.footnote)
                .foregroundStyle(SomatiqColor.textSecondary)
        }
    }

    private func errorSection(message: String) -> some View {
        Section("Status") {
            Text(message)
                .font(.footnote)
                .foregroundStyle(SomatiqColor.warning)

            Button("Retry Load") {
                viewModel.load()
            }
            .buttonStyle(.bordered)
            .tint(SomatiqColor.accent)
        }
    }

    private var birthYearTextBinding: Binding<String> {
        Binding {
            if let birthYear = viewModel.birthYear {
                return String(birthYear)
            }
            return ""
        } set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                viewModel.birthYear = nil
            } else {
                viewModel.birthYear = Int(trimmed)
            }
        }
    }

}
