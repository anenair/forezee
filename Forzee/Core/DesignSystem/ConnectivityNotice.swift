// ============================================================
// ConnectivityNotice.swift
// Forzee — Core/DesignSystem
//
// Kai is AI-centric — every chat reply, workout generation, and
// voice command needs a live network call. A dead connection
// reflects badly on the app if it just looks unresponsive, so
// this surfaces it explicitly wherever AI is actually invoked.
//
// Distinct from the sync-status row in Settings: that one is about
// whether saved data (workouts, nutrition) has reached the server
// yet — it always succeeds locally regardless of connectivity. This
// is specifically "the thing you're about to do needs Kai, and Kai
// needs a connection right now."
// ============================================================

import SwiftUI

struct ConnectivityNotice: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13))
                .foregroundStyle(Color.fzOrange)
                .padding(.top, 1)
            Text(message)
                .font(.fzBody(13))
                .foregroundStyle(Color.fzTextSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fzOrange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.chip)
                .strokeBorder(Color.fzOrange.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    ConnectivityNotice(message: "No connection — Kai can't chat right now.")
        .padding(24)
        .background(Color.fzBg)
}
