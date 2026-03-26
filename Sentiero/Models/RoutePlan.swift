//
//  RoutePlan.swift
//  Sentiero
//
//  Created by Nirav Tailor on 26/02/2026.
//


import Foundation

struct RoutePlan: Identifiable, Codable, Hashable {
    /// Firestore document id under `activePlans` — unique per saved plan (not the same as `route.id`).
    let id: String
    /// Shown in the plans list; user can rename without changing the underlying route metadata.
    var displayTitle: String
    var route: TrekRoute
    var checklist: [ChecklistItem]

    init(id: String = UUID().uuidString, route: TrekRoute, checklist: [ChecklistItem] = [], displayTitle: String? = nil) {
        self.id = id
        self.route = route
        self.checklist = checklist
        self.displayTitle = displayTitle ?? route.name
    }

    enum CodingKeys: String, CodingKey {
        case id, displayTitle, route, checklist
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        route = try c.decode(TrekRoute.self, forKey: .route)
        checklist = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle) ?? route.name
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(displayTitle, forKey: .displayTitle)
        try c.encode(route, forKey: .route)
        try c.encode(checklist, forKey: .checklist)
    }

    static func == (lhs: RoutePlan, rhs: RoutePlan) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}