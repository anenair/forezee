// ============================================================
// ForzeeButton.swift
// Forzee — Core/DesignSystem
//
// Primary full-width CTA button used throughout the app.
// Matches the design spec from forezee.pen:
//   - Height: 48pt
//   - Corner radius: 14
//   - Fill: fzPrimary (#B8A832)
//   - Text: fzMono 14pt medium, dark (#0A0A0F)
//   - Interaction: scale 0.97, darken 8%, inner shadow on press
//   - Haptic: light impact on press
// ============================================================

import SwiftUI

// MARK: - ForzeeButton

struct ForzeeButton: View {

    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    var isLoading: Bool = false

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(Color(hex: "0A0A0F"))
                        .scaleEffect(0.9)
                } else {
                    Text(title)
                        .font(.fzMono(14, weight: .medium))
                        .foregroundStyle(Color(hex: "0A0A0F"))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: ForzeeRadius.button)
                    .fill(isDisabled ? Color.fzPrimary.opacity(0.35) : Color.fzPrimary)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .disabled(isDisabled || isLoading)
        .buttonStyle(PressedButtonStyle(isPressed: $isPressed))
    }
}

// MARK: - ForzeeTextButton

/// Secondary / ghost link button — used for "I already have an account", "Set up later", etc.
struct ForzeeTextButton: View {

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.fzBody(14, weight: .medium))
                .foregroundStyle(Color.fzTextSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PressedButtonStyle

/// Captures press state for scale animation without overriding default button behavior.
private struct PressedButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ForzeeButton(title: "Get Started") {}
        ForzeeButton(title: "Continue") {}
        ForzeeButton(title: "Disabled", action: {}, isDisabled: true)
        ForzeeButton(title: "Loading", action: {}, isLoading: true)
        ForzeeTextButton(title: "I already have an account") {}
    }
    .padding(24)
    .background(Color.fzBg)
}
