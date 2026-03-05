import SwiftUI

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var showingWatchPairingHelp = false
    @State private var sectionsAppeared = false
    @State private var scrollOffset: CGFloat = 0

    init(settingsService: SettingsDataService) {
        _viewModel = State(initialValue: SettingsViewModel(settingsService: settingsService))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    SomatiqColor.bg.ignoresSafeArea()

                    ScrollView {
                        SomatiqScrollOffsetReader(coordinateSpace: "settingsScroll")
                        VStack(alignment: .leading, spacing: 20) {
                            header
                                .modifier(SettingsSectionEntrance(index: 0, appeared: sectionsAppeared))
                            sectionTitle("Profile")
                                .modifier(SettingsSectionEntrance(index: 1, appeared: sectionsAppeared))
                            profileCard
                                .modifier(SettingsSectionEntrance(index: 2, appeared: sectionsAppeared))
                            sectionTitle("Health Data")
                                .modifier(SettingsSectionEntrance(index: 3, appeared: sectionsAppeared))
                            healthCard
                                .modifier(SettingsSectionEntrance(index: 4, appeared: sectionsAppeared))
                            sectionTitle("About")
                                .modifier(SettingsSectionEntrance(index: 5, appeared: sectionsAppeared))
                            aboutCard
                                .modifier(SettingsSectionEntrance(index: 6, appeared: sectionsAppeared))

                            if let errorMessage = viewModel.errorMessage {
                                statusCard(message: errorMessage)
                                    .modifier(SettingsSectionEntrance(index: 7, appeared: sectionsAppeared))
                            }

                            Spacer(minLength: 90)
                        }
                        .padding(.horizontal, SomatiqSpacing.pageHorizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }
                    .coordinateSpace(name: "settingsScroll")
                    .scrollIndicators(.hidden)

                    SomatiqProgressiveHeaderBar(
                        title: "Settings",
                        subtitle: nil,
                        progress: headerProgress,
                        topInset: proxy.safeAreaInsets.top
                    )
                }
                .onPreferenceChange(SomatiqScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
            }
            .task {
                viewModel.load()
                withAnimation(SomatiqAnimation.sectionReveal) {
                    sectionsAppeared = true
                }
            }
        }
        .tint(SomatiqColor.accent)
        .sheet(isPresented: $showingWatchPairingHelp) {
            watchPairingHelpSheet
                .presentationDetents([.medium, .large])
                .presentationBackground(SomatiqColor.bg)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Settings")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(SomatiqColor.textPrimary)

            Spacer()

            Button {
                viewModel.save()
            } label: {
                Text(viewModel.isSaving ? "Saving..." : "Save")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [SomatiqColor.accent, SomatiqColor.sleep],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.24), SomatiqColor.accent.opacity(0.35), Color.white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.95
                            )
                    }
                    .contentTransition(.opacity)
            }
            .somatiqShadow(tint: SomatiqColor.accent, intensity: .prominent)
            .disabled(viewModel.isSaving)
            .buttonStyle(.somatiqPressable)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(SomatiqColor.textMuted)
    }

    private var profileCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                TextField("Name", text: Binding(
                    get: { viewModel.name },
                    set: { viewModel.name = $0 }
                ))
                .textInputAutocapitalization(.words)
                .foregroundStyle(SomatiqColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

                rowDivider

                HStack(spacing: 12) {
                    Text("Sleep target: \(viewModel.targetSleepHours, specifier: "%.1f")h")
                        .font(.system(size: 16))
                        .foregroundStyle(SomatiqColor.textPrimary)
                    Spacer()
                    sleepTargetControl
                }

                rowDivider

                HStack(spacing: 12) {
                    Text("Birth year")
                        .font(.system(size: 16))
                        .foregroundStyle(SomatiqColor.textPrimary)
                    Spacer()
                    TextField("Optional", text: birthYearTextBinding)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                        .foregroundStyle(SomatiqColor.textSecondary)
                }
            }
        }
    }

    private var sleepTargetControl: some View {
        HStack(spacing: 0) {
            Button {
                adjustSleepTarget(by: -0.5)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 38)
            }
            .disabled(viewModel.targetSleepHours <= 5)
            .buttonStyle(.somatiqPressable)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 22)

            Button {
                adjustSleepTarget(by: 0.5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 38)
            }
            .disabled(viewModel.targetSleepHours >= 10)
            .buttonStyle(.somatiqPressable)
        }
        .foregroundStyle(SomatiqColor.textPrimary)
        .background(
            LinearGradient(
                colors: [Color(hex: "#1B1D2A"), Color(hex: "#10111A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        }
    }

    private func adjustSleepTarget(by value: Double) {
        withAnimation(SomatiqAnimation.press) {
            viewModel.targetSleepHours = min(max(viewModel.targetSleepHours + value, 5), 10)
        }
    }

    private var healthCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Button(viewModel.isAuthorizing ? "Connecting..." : "Reconnect Apple Health") {
                    Task {
                        await viewModel.reconnectHealth()
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SomatiqColor.accent)
                .contentTransition(.opacity)
                .disabled(viewModel.isAuthorizing)
                .buttonStyle(.somatiqPressable)

                rowDivider

                HStack {
                    Text("Apple Watch")
                        .font(.system(size: 16))
                        .foregroundStyle(SomatiqColor.textPrimary)
                    Spacer()
                    Text(viewModel.appleWatchStatusTitle)
                        .font(.system(size: 16))
                        .foregroundStyle(SomatiqColor.textTertiary)
                        .contentTransition(.opacity)
                }

                rowDivider

                HStack {
                    Text("Last sync")
                        .font(.system(size: 16))
                        .foregroundStyle(SomatiqColor.textPrimary)
                    Spacer()
                    Text(viewModel.lastSyncText)
                        .font(.system(size: 16))
                        .foregroundStyle(SomatiqColor.textTertiary)
                        .contentTransition(.opacity)
                }

                Text(viewModel.appleWatchStatusHint)
                    .font(.footnote)
                    .foregroundStyle(SomatiqColor.textSecondary)
                    .padding(.top, 2)

                if viewModel.shouldShowWatchPairingHelp {
                    Button("How to pair Apple Watch") {
                        showingWatchPairingHelp = true
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SomatiqColor.accent)
                    .padding(.top, 2)
                    .buttonStyle(.somatiqPressable)
                }
            }
        }
    }

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Version")
                        .font(.system(size: 16))
                        .foregroundStyle(SomatiqColor.textPrimary)
                    Spacer()
                    Text("1.0.0")
                        .font(.system(size: 16))
                        .foregroundStyle(SomatiqColor.textTertiary)
                }

                rowDivider

                Link("Source Code (GitHub)", destination: URL(string: "https://github.com")!)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SomatiqColor.accent)

                rowDivider

                Text("All health data is stored on this device only.")
                    .font(.footnote)
                    .foregroundStyle(SomatiqColor.textSecondary)
                Text("Somatiq provides wellness insights only and is not a medical device.")
                    .font(.footnote)
                    .foregroundStyle(SomatiqColor.textSecondary)
            }
        }
    }

    private func statusCard(message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Status")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SomatiqColor.textPrimary)

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
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
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

    private var watchPairingHelpSheet: some View {
        NavigationStack {
            List {
                Section("Pairing is done in Apple apps") {
                    Text("Somatiq cannot pair Apple Watch directly. Pairing is managed by iOS.")
                        .foregroundStyle(SomatiqColor.textSecondary)
                }

                Section("Steps") {
                    Text("1. Open the Watch app on iPhone.")
                    Text("2. Tap \"Start Pairing\" or \"Pair New Watch\".")
                    Text("3. Keep watch unlocked and on your wrist.")
                    Text("4. Open Apple Health once to let data sync.")
                    Text("5. Return to Somatiq and tap Reconnect Apple Health.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SomatiqColor.bg.ignoresSafeArea())
            .navigationTitle("Apple Watch Setup")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingWatchPairingHelp = false
                    }
                }
            }
        }
    }

    private var headerProgress: CGFloat {
        CGFloat(Statistics.clamped(Double((-scrollOffset - 8) / 68), min: 0, max: 1))
    }
}

private struct SettingsSectionEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let index: Int
    let appeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(
                reduceMotion ? .linear(duration: 0.1) : SomatiqAnimation.staggered(index: index),
                value: appeared
            )
    }
}
