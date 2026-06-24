import SwiftUI

/// Routes between the calm Paper meta screens and the dark Arena run. The background
/// crossfades paper↔ink as the player steps into/out of a run — the branded transition
/// (§5.3).
struct RootView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.scenePhase) private var scenePhase

    private var isArena: Bool { store.phase == .countdown || store.phase == .run }

    var body: some View {
        ZStack {
            (isArena ? Palette.ink : Palette.paper).ignoresSafeArea()

            switch store.phase {
            case .loading:    LoadingView()
            case .onboarding: OnboardingView()
            case .home:       HomeView()
            case .countdown:  CountdownView()
            case .run:        RunView()
            case .result:     ResultView()
            }
        }
        .animation(.easeInOut(duration: Metrics.bank), value: isArena)
        .statusBarHidden(isArena)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { store.handleBecameActive() }
        }
    }
}

struct LoadingView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        VStack(spacing: Metrics.s6) {
            Wordmark(color: Palette.onPaperPrimary, size: 56)
            if store.loadFailed {
                Text("Couldn't load today's board.")
                    .font(Type.body)
                    .foregroundStyle(Palette.onPaperSecondary)
            } else {
                ProgressView().tint(Palette.taupe)
                Text("Preparing today's board")
                    .font(Type.caption)
                    .foregroundStyle(Palette.onPaperSecondary)
            }
        }
    }
}
