//
//  ChecklistItem.swift
//  Sentiero
//
//  Created by Nirav Tailor on 26/02/2026.
//


import Foundation

struct ChecklistItem: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    let title: String
    /// Built-in groups: Essentials, Clothing & Weather, Navigation & Safety. Gemini may add more (e.g. "Nutrition & Hydration").
    let category: String
    var isCompleted: Bool = false

    static let builtInCategories: [String] = [
        "Essentials",
        "Clothing & Weather",
        "Navigation & Safety",
    ]

    /// Maps API / legacy labels onto canonical built-in names when close enough; otherwise keeps a trimmed custom title.
    static func normalizeCategory(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return builtInCategories[0] }

        let lower = t.lowercased()
        for built in builtInCategories where built.lowercased() == lower {
            return built
        }

        let aliases: [String: String] = [
            "essential": builtInCategories[0],
            "essentials": builtInCategories[0],
            "clothing": builtInCategories[1],
            "clothing & weather": builtInCategories[1],
            "weather": builtInCategories[1],
            "clothing and weather": builtInCategories[1],
            "navigation": builtInCategories[2],
            "navigation & safety": builtInCategories[2],
            "navigation and safety": builtInCategories[2],
            "safety": builtInCategories[2],
        ]
        if let mapped = aliases[lower] { return mapped }

        if lower.contains("essential") { return builtInCategories[0] }
        if lower.contains("cloth") || lower.contains("weather") { return builtInCategories[1] }
        if lower.contains("navigat") || lower.contains("safety") { return builtInCategories[2] }

        return t
    }
}
