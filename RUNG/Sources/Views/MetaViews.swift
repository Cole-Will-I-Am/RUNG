import SwiftUI
import AuthenticationServices

// Calm Paper-mode meta screens (§5.1): onboarding, stats, leaderboard, settings.

private struct SheetHeader: View {
    let title: String
    let onDone: () -> Void
    var body: some View {
        HStack {
            Text(title).font(Type.h1).foregroundStyle(Palette.onPaperPrimary)
            Spacer()
            Button("Done", action: onDone)
                .font(Type.body)
                .foregroundStyle(Palette.onPaperPrimary)
        }
    }
}

private struct StatBox: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(Type.instrumentStd)
                .monospacedDigit()
                .foregroundStyle(Palette.onPaperPrimary)
            Text(label)
                .font(Type.label)
                .foregroundStyle(Palette.onPaperSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.s4)
        .background(RoundedRectangle(cornerRadius: Metrics.radiusCard).fill(Palette.paperDeep))
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s6) {
            Spacer()
            Wordmark(color: Palette.onPaperPrimary, size: 56)
            Text("A word game you play once a day.")
                .font(Type.h1)
                .foregroundStyle(Palette.onPaperPrimary)

            VStack(alignment: .leading, spacing: Metrics.s4) {
                howRow("1", "Everyone gets the same twelve letters.")
                howRow("2", "Find words in 60 seconds. Each one lifts your multiplier.")
                howRow("3", "Bank to lock in your score — or push your luck and risk it.")
            }
            Spacer()
            PrimaryButton(title: "Begin") { store.finishOnboarding() }
        }
        .padding(.horizontal, Metrics.s6)
        .padding(.vertical, Metrics.s8)
    }

    private func howRow(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: Metrics.s3) {
            Text(n).font(Type.instrumentStd).foregroundStyle(Palette.taupe)
            Text(t).font(Type.body).foregroundStyle(Palette.onPaperPrimary)
        }
    }
}

// MARK: - Stats

struct StatsView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        let s = store.stats
        VStack(alignment: .leading, spacing: Metrics.s6) {
            SheetHeader(title: "Stats") { dismiss() }
            LazyVGrid(columns: cols, spacing: Metrics.s3) {
                StatBox(label: "current streak", value: "\(s.currentStreak)")
                StatBox(label: "best streak", value: "\(s.bestStreak)")
                StatBox(label: "best score", value: ShareCard.decimal(s.bestScore))
                StatBox(label: "runs played", value: "\(s.totalRuns)")
                StatBox(label: "recent average", value: ShareCard.decimal(s.averageScore))
            }
            Spacer()
        }
        .padding(Metrics.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper.ignoresSafeArea())
    }
}

// MARK: - Leaderboard

struct LeaderboardView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var period = "daily"

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s4) {
            SheetHeader(title: "Leaderboard") { dismiss() }

            Picker("", selection: $period) {
                Text("Today").tag("daily")
                Text("All-time").tag("alltime")
            }
            .pickerStyle(.segmented)
            .onChange(of: period) { _, p in store.fetchLeaderboard(period: p) }

            if let me = store.leaderboard?.me, period == "daily" {
                Text("You're #\(me.rank) — top \(topPercent(me.percentile))% today.")
                    .font(Type.caption)
                    .foregroundStyle(Palette.onPaperSecondary)
            }

            if let lb = store.leaderboard, !lb.entries.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(lb.entries.enumerated()), id: \.offset) { i, e in
                            row(rank: i + 1, e: e)
                        }
                    }
                }
            } else {
                Spacer()
                Text(store.leaderboard == nil ? "Loading…" : "No scores yet. Be the first to climb.")
                    .font(Type.body)
                    .foregroundStyle(Palette.onPaperSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper.ignoresSafeArea())
        .onAppear { period = store.leaderboardPeriod; store.fetchLeaderboard(period: period) }
    }

    private func topPercent(_ beaten: Double) -> Int { max(1, Int((100 - beaten).rounded())) }

    private func row(rank: Int, e: LeaderboardEntry) -> some View {
        let mine = e.id == store.account?.id
        return HStack {
            Text("\(rank)")
                .font(Type.instrumentStd)
                .foregroundStyle(Palette.taupe)
                .frame(width: 34, alignment: .leading)
            Text(e.name)
                .font(Type.body)
                .foregroundStyle(Palette.onPaperPrimary)
            Spacer()
            Text(ShareCard.decimal(e.score))
                .font(Type.instrumentStd)
                .monospacedDigit()
                .foregroundStyle(Palette.onPaperPrimary)
        }
        .padding(.vertical, Metrics.s3)
        .padding(.horizontal, Metrics.s3)
        .background(RoundedRectangle(cornerRadius: 10).fill(mine ? Palette.paperDeep : Color.clear))
        .overlay(Rectangle().fill(Palette.hairlineOnPaper).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var notify = false
    @State private var rawNonce = ""
    @State private var usernameInput = ""
    @State private var usernameMsg: String?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.s6) {
                SheetHeader(title: "Settings") { dismiss() }

                VStack(alignment: .leading, spacing: Metrics.s3) {
                    Text("Account").font(Type.label).foregroundStyle(Palette.onPaperSecondary)
                    if store.isSignedIn {
                        Text("Signed in as \(store.account?.username ?? store.account?.display ?? "—")")
                            .font(Type.body).foregroundStyle(Palette.onPaperPrimary)
                        HStack(spacing: Metrics.s2) {
                            TextField("username", text: $usernameInput)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(Type.body).padding(.horizontal, Metrics.s3).frame(height: 44)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.paperDeep))
                            Button("Save") { Task { usernameMsg = await store.setUsername(usernameInput) } }
                                .font(Type.label).foregroundStyle(Palette.onPaperPrimary)
                        }
                        if let m = usernameMsg {
                            Text(m).font(Type.caption).foregroundStyle(Palette.onPaperSecondary)
                        }
                    } else {
                        Text("Sign in to claim a username and compete under your name. Anonymous scores still rank — sign-in just makes it yours across devices.")
                            .font(Type.caption).foregroundStyle(Palette.onPaperSecondary)
                        SignInWithAppleButton(.signIn) { request in
                            rawNonce = AppleSignIn.randomNonce()
                            request.requestedScopes = [.fullName]
                            request.nonce = AppleSignIn.sha256Hex(rawNonce)
                        } onCompletion: { result in
                            if case .success(let auth) = result,
                               let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                               let data = cred.identityToken,
                               let idToken = String(data: data, encoding: .utf8) {
                                store.signInWithApple(identityToken: idToken, nonce: rawNonce)
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                Rectangle().fill(Palette.hairlineOnPaper).frame(height: 1)

                Toggle(isOn: $notify) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily reminder").font(Type.body).foregroundStyle(Palette.onPaperPrimary)
                        Text("One calm notification when the board goes live.")
                            .font(Type.caption).foregroundStyle(Palette.onPaperSecondary)
                    }
                }
                .tint(Palette.ink)
                .onChange(of: notify) { _, v in store.setNotifications(v) }

                Rectangle().fill(Palette.hairlineOnPaper).frame(height: 1)

                VStack(alignment: .leading, spacing: Metrics.s2) {
                    Text("About").font(Type.label).foregroundStyle(Palette.onPaperSecondary)
                    Text("RUNG is an early, experimental build. The name is a working title.")
                        .font(Type.caption).foregroundStyle(Palette.onPaperSecondary)
                    Text("Version \(appVersion)")
                        .font(Type.instrumentMicro).foregroundStyle(Palette.taupe)
                }

                Button(role: .destructive) { confirmDelete = true } label: {
                    Text("Delete account").font(Type.label)
                }
                .tint(Color(hex: 0x9A4A3C))   // desaturated system-danger, distinct from heat (§3.4)
            }
            .padding(Metrics.s6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper.ignoresSafeArea())
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await store.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your scores, streak, and leaderboard history. This can't be undone.")
        }
        .onAppear { notify = store.notificationsOn; usernameInput = store.account?.username ?? "" }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}
