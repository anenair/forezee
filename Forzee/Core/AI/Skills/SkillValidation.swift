// ============================================================
// SkillValidation.swift
// Forzee — Core/AI/Skills
//
// DEBUG-only launch check. Text files bundled as resources fail
// at runtime, not compile time — a typo'd frontmatter field or
// broken JSON in a skill's tool schema would otherwise surface
// the first time a real user's message happens to trigger it in
// production. Re-parses every bundled skill file directly (not
// through SkillLoader's silent skip-on-failure) and asserts
// loudly on the first one that doesn't parse, so a broken skill
// is caught while writing it.
// ============================================================

import Foundation

enum SkillValidation {

    #if DEBUG
    static func assertAllSkillsValid() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: "Skills") ?? []
        assert(
            !urls.isEmpty,
            "SkillValidation: no .md files found under Skills/ — check the folder reference in project.yml."
        )

        for url in urls {
            do {
                let raw = try String(contentsOf: url, encoding: .utf8)
                _ = try SkillParser.parse(raw)
            } catch {
                assertionFailure("SkillValidation: \(url.lastPathComponent) failed to parse — \(error.localizedDescription)")
            }
        }
    }
    #endif
}
