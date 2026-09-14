// ============================================================
// SignUpView.swift
// Forzee — Features/Auth
//
// Creates a Supabase auth user + profile row (the DB trigger
// handles the profile insert), then hands off to AppState so
// RootView routes into onboarding.
// ============================================================

import SwiftUI

struct SignUpView: View {

    let onBack: () -> Void
    let onSwitchToSignIn: () -> Void

    @EnvironmentObject private var appState: AppState

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthHeader(title: "Create Account", onBack: onBack)

            VStack(spacing: ForzeeSpacing.itemGap) {
                AuthField(label: "Full name (optional)", text: $fullName, textContentType: .name)
                AuthField(
                    label: "Email", text: $email,
                    keyboardType: .emailAddress, textContentType: .emailAddress
                )
                AuthField(
                    label: "Password (6+ characters)", text: $password,
                    isSecure: true, textContentType: .newPassword
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
                    title: "Create Account", action: submit,
                    isDisabled: !canSubmit, isLoading: isSubmitting
                )
                ForzeeTextButton(title: "I already have an account", action: onSwitchToSignIn)
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
                let userId = try await ForzeeDataService.shared.signUp(
                    email: email,
                    password: password,
                    fullName: fullName.isEmpty ? nil : fullName
                )
                await appState.completeSignIn(userId: userId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    SignUpView(onBack: {}, onSwitchToSignIn: {})
        .environmentObject(AppState())
        .forzeeBackground()
}
