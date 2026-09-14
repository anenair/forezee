// ============================================================
// AuthComponents.swift
// Forzee — Features/Auth
//
// Shared pieces for SignUpView / SignInView: a labeled text
// field styled to match MacroField/OnboardingProgressBar's
// fzSurface-chip look, and a back-button header.
// ============================================================

import SwiftUI

// MARK: - AuthField

struct AuthField: View {
    let label: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.fzBody(13))
                .foregroundStyle(Color.fzTextSecondary)

            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(textContentType)
            .font(.fzBody(16))
            .foregroundStyle(Color.fzText)
            .padding(14)
            .background(Color.fzSurface)
            .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
        }
    }
}

// MARK: - AuthHeader

struct AuthHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.fzText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .overlay(
            Text(title)
                .font(.fzHeading(17, weight: .semibold))
                .foregroundStyle(Color.fzText)
        )
        .padding(.top, 8)
    }
}
