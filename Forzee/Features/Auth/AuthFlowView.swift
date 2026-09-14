// ============================================================
// AuthFlowView.swift
// Forzee — Features/Auth
//
// Shown by RootView while !appState.isAuthenticated. Three
// steps: hero welcome → sign up or sign in. On success,
// AppState.completeSignIn flips isAuthenticated and RootView
// takes over routing into onboarding or the main app.
// ============================================================

import SwiftUI

struct AuthFlowView: View {

    private enum Step: Equatable {
        case welcome, signUp, signIn
    }

    @State private var step: Step = .welcome

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            switch step {
            case .welcome:
                AuthWelcomeView(
                    onGetStarted: { withAnimation { step = .signUp } },
                    onAlreadyHaveAccount: { withAnimation { step = .signIn } }
                )
            case .signUp:
                SignUpView(
                    onBack: { withAnimation { step = .welcome } },
                    onSwitchToSignIn: { withAnimation { step = .signIn } }
                )
            case .signIn:
                SignInView(
                    onBack: { withAnimation { step = .welcome } },
                    onSwitchToSignUp: { withAnimation { step = .signUp } }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }
}

#Preview {
    AuthFlowView()
        .environmentObject(AppState())
}
