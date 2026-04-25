// ============================================================
// OnboardingEquipmentView.swift
// Forzee — Features/Onboarding
//
// Design reference: forezee.pen → "5. Onboarding Equipment" (QDw8d)
//
// Layout:
//   - Progress bar (3/5)
//   - "Step 3 of 5" label
//   - "What do you have access to?" heading
//   - 3×2 equipment grid (each cell 110pt height)
//   - "Continue" primary button
//
// Grid cell states:
//   Selected:   fzSurface, fzPrimary border 2pt, fzPrimary icon
//   Unselected: fzSurface, fzBorder 1pt, fzTextSecondary icon
// ============================================================

import SwiftUI

struct OnboardingEquipmentView: View {

    @EnvironmentObject private var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 62)

                VStack(alignment: .leading, spacing: 24) {
                    // ── Progress + Step Label ────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        OnboardingProgressBar(step: 3)
                        Text("Step 3 of 5")
                            .font(.fzBody(13, weight: .medium))
                            .foregroundStyle(Color.fzPrimary)
                    }

                    // ── Heading ──────────────────────────────────
                    Text("What do you have\naccess to?")
                        .font(.fzHeading(28, weight: .bold))
                        .foregroundStyle(Color.fzText)
                        .lineSpacing(28 * 0.2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // ── Equipment Grid ───────────────────────────
                    VStack(spacing: 12) {
                        ForEach(Equipment.displayGrid, id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(row) { item in
                                    EquipmentCell(
                                        equipment: item,
                                        isSelected: viewModel.selectedEquipment.contains(item),
                                        onTap: { toggleEquipment(item) }
                                    )
                                }
                            }
                        }
                    }

                    Spacer()

                    // ── Continue ────────────────────────────────
                    ForzeeButton(
                        title: "Continue",
                        action: onContinue,
                        isDisabled: !viewModel.canContinueFromEquipment
                    )
                    .padding(.bottom, ForzeeSpacing.screenPadding)
                }
                .padding(.horizontal, ForzeeSpacing.screenPadding)
                .padding(.top, ForzeeSpacing.screenPadding)
            }
        }
    }

    private func toggleEquipment(_ item: Equipment) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if viewModel.selectedEquipment.contains(item) {
            viewModel.selectedEquipment.remove(item)
        } else {
            viewModel.selectedEquipment.insert(item)
        }
    }
}

// MARK: - EquipmentCell

private struct EquipmentCell: View {

    let equipment: Equipment
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: equipment.iconSystemName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(isSelected ? Color.fzPrimary : Color.fzTextSecondary)

                Text(equipment.label)
                    .font(.fzBody(13, weight: .medium))
                    .foregroundStyle(Color.fzText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .padding(16)
            .background(Color.fzSurface)
            .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: ForzeeRadius.card)
                    .strokeBorder(
                        isSelected ? Color.fzPrimary : Color.fzBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingEquipmentView(onContinue: {})
        .environmentObject(OnboardingViewModel())
}
