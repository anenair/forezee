// ============================================================
// OnboardingFlow.swift
// Forzee — Features/Onboarding
//
// Navigation coordinator for the full onboarding sequence:
//
//   Splash → Welcome → Step 1 (Fitness Level) → Step 2 (Goals)
//   → Step 3 (Equipment) → Step 4 (Schedule)
//   → Permissions → Meet Kai → [App Main Tab View]
//
// Uses a custom step-based navigation rather than NavigationStack
// so transitions can be precisely controlled per step.
// Back navigation is supported for steps 1-4.
// ============================================================

import SwiftUI

// MARK: - OnboardingStep

enum OnboardingStep: Int, CaseIterable {
    case splash        = 0
    case welcome       = 1
    case fitnessLevel  = 2
    case goals         = 3
    case equipment     = 4
    case schedule      = 5
    case permissions   = 6
    case meetKai       = 7

    var showsProgressBar: Bool {
        switch self {
        case .fitnessLevel, .goals, .equipment, .schedule: return true
        default: return false
        }
    }

    /// 1-based step index shown in the progress bar (nil if not shown)
    var progressStep: Int? {
        switch self {
        case .fitnessLevel: return 1
        case .goals:        return 2
        case .equipment:    return 3
        case .schedule:     return 4
        default:            return nil
        }
    }

    var showsBackButton: Bool {
        switch self {
        case .welcome, .fitnessLevel, .goals, .equipment, .schedule: return false
        case .permissions: return true
        default: return false
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        guard rawValue > 0 else { return nil }
        return OnboardingStep(rawValue: rawValue - 1)
    }
}

// MARK: - OnboardingFlowView

struct OnboardingFlowView: View {

    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var step: OnboardingStep = .splash
    @State private var direction: NavigationDirection = .forward

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            currentScreen
                .transition(transition(for: direction))
                .id(step) // Forces SwiftUI to re-render on step change
        }
        .animation(.easeInOut(duration: 0.35), value: step)
        .environmentObject(viewModel)
    }

    // MARK: - Current Screen

    @ViewBuilder
    private var currentScreen: some View {
        switch step {
        case .splash:
            SplashView { advance() }

        case .welcome:
            OnboardingWelcomeView(
                onGetStarted: { advance() },
                onAlreadyHaveAccount: { /* TODO: Route to sign-in */ }
            )

        case .fitnessLevel:
            OnboardingFitnessLevelView(onSelect: { advance() })

        case .goals:
            OnboardingGoalsView(onContinue: { advance() })

        case .equipment:
            OnboardingEquipmentView(onContinue: { advance() })

        case .schedule:
            OnboardingScheduleView(onContinue: { advance() })

        case .permissions:
            OnboardingPermissionsView(
                onGrantAll: { advance() },
                onSetUpLater: { advance() },
                onBack: { goBack() }
            )

        case .meetKai:
            MeetKaiView(onLetsGo: {
                Task { await completeOnboarding() }
            })
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard let next = step.next else { return }
        direction = .forward
        withAnimation { step = next }
    }

    private func goBack() {
        guard let prev = step.previous else { return }
        direction = .backward
        withAnimation { step = prev }
    }

    private func completeOnboarding() async {
        guard let userId = appState.userId else { return }
        await viewModel.complete(userId: userId)
        appState.onboardingComplete = true
    }

    // MARK: - Transition

    private func transition(for direction: NavigationDirection) -> AnyTransition {
        switch direction {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
}

// MARK: - NavigationDirection

private enum NavigationDirection {
    case forward, backward
}
