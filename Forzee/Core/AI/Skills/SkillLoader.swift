// ============================================================
// SkillLoader.swift
// Forzee — Core/AI/Skills
//
// Auto-discovery: scans the bundled Skills/ folder itself rather
// than reading a hardcoded list of filenames. Skills/ is added to
// the Xcode project as a folder reference (see project.yml), so a
// new .md file dropped in there is a new skill the next time this
// runs — nothing to register, no enum case to add, no rebuild to
// edit wording. A skill that fails to parse is skipped here
// (best-effort, matches the rest of the app's read-path policy)
// rather than crashing a real user's launch — see SkillValidation
// for the DEBUG-only version that fails loudly instead.
// ============================================================

import Foundation

final class SkillLoader {

    static let shared = SkillLoader()

    private(set) var skills: [Skill] = []
    private var byName: [String: Skill] = [:]

    private init() {
        reload()
    }

    /// Re-scans the bundle for every .md file under Skills/ and parses each
    /// into a Skill. Called once at init; exposed so SkillValidation and
    /// tests can force a fresh parse.
    func reload() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: "Skills") ?? []

        var loaded: [Skill] = []
        var index: [String: Skill] = [:]

        for url in urls {
            guard let raw = try? String(contentsOf: url, encoding: .utf8),
                  let skill = try? SkillParser.parse(raw) else {
                #if DEBUG
                print("SkillLoader: failed to parse \(url.lastPathComponent) — skipping.")
                #endif
                continue
            }
            loaded.append(skill)
            index[skill.name] = skill
        }

        skills = loaded.sorted { $0.name < $1.name }
        byName = index
    }

    func skill(named name: String) -> Skill? {
        byName[name]
    }
}
