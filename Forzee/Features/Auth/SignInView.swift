// ============================================================
// SignInView.swift
// Forzee — Features/Auth
// ============================================================

import SwiftUI

struct SignInView: View {

    let onBack: () -> Void
    let onSwitchToSignUp: () -> Void

    @EnvironmentObject private var appState: AppState

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthHeader(title: "Sign In", onBack: onBack)

            VStack(spacing: ForzeeSpacing.itemGap) {
                AuthField(
                    label: "Email", text: $email,
                    keyboardType: .emailAddress, textContentType: .emailAddress
                )
                AuthField(
                    label: "Password", text: $password,
                    isSecure: true, textContentType: .password
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.fzBody(13))
                        .foregroundStyle(Color.fzPink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, ForzeeSpacing.sectionGap)

            Spacer()

            VStack(spacing: 16) {
                ForzeeButton(
                    title: "Sign In", action: submit,
                    isDisabled: !canSubmit, isLoading: isSubmitting
                )
                ForzeeTextButton(title: "Create an account instead", action: onSwitchToSignUp)
            }
        }
        .padding(ForzeeSpacing.screenPadding)
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let userId = try await ForzeeDataService.shared.signIn(email: email, password: password)
                await appState.completeSignIn(userId: userId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    SignInView(onBack: {}, onSwitchToSignUp: {})
        .environmentObject(AppState())
        .forzeeBackground()
}
