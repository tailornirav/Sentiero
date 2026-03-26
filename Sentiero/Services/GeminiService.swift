import Foundation
import CoreLocation

class GeminiService {
    static let shared = GeminiService()

    private var apiKey: String { APIConfig.geminiAPIKey }
    /// Main AI route JSON generation.
    private let model = "gemini-2.5-pro"
    /// Fast model for per-segment difficulty (public-route coloring); keeps payloads small and avoids flaky responses.
    private let segmentAnalysisModel = "gemini-2.5-flash"
    
    private lazy var geminiURLSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
    
    // MARK: - The Async Pipeline
    
    func generateRoute(from userPrompt: String, userLocation: CLLocationCoordinate2D?) async throws -> TrekRoute {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let currentTime = Date().formatted(date: .abbreviated, time: .shortened)
        
        let gpsContext = userLocation != nil
            ? "\(userLocation!.latitude), \(userLocation!.longitude)"
            : "Not Available"
        
        // Your highly structured logical prompt
        let systemInstruction = """
        You are a highly precise Topographical Route Engine. 
        Your sole task is to act as a structured program that generates valid, detailed outdoor routes based strictly on the user's input.
        
        CONTEXT:
        - Current Time: \(currentTime)
        - User's Device GPS: \(gpsContext)
        - User Request: "\(userPrompt)"
        
        CRITICAL LOGIC & RULES:
        1. LOCATION MAPPING:
           - Analyze the 'User Request'. If it mentions a specific place (e.g., "Paris", "Lake District", "Hyde Park"), IGNORE the Device GPS and generate the route in the requested place.
           - If the request says "here", "nearby", "near me", or mentions no location, USE the Device GPS as the exact starting point.
        
        2. ACTIVITY MAPPING: 
           - You MUST output EXACTLY ONE of these strings for activity_type: "Hiking", "Cycling", "Mountain Biking", "Equestrian".
           - Analyze the 'User Request':
             * If it mentions "cycle", "bike", "biking", "road bike" -> output "Cycling"
             * If it mentions "mountain bike", "mtb", "trail riding", "dirt jumps" -> output "Mountain Biking"
             * If it mentions "horse", "equestrian", "riding" -> output "Equestrian"
             * If it mentions "walk", "hike", "trek", "run" or is ambiguous -> output "Hiking"
        
        3. DIFFICULTY MAPPING: 
           - You MUST output EXACTLY ONE of these strings for difficulty_rating: "Easy", "Moderate", "Hard".
           - Analyze the route distance, elevation, and the 'User Request' to determine the difficulty.
        
        4. POLYLINE INTEGRITY (EXTREMELY IMPORTANT): 
           - You MUST generate an array of 15 to 25 REAL, sequential geographic coordinates.
           - DO NOT duplicate coordinates. Every single coordinate MUST have slightly different latitude and longitude values to simulate a physical path.
           - Ensure the coordinates are spaced logically so they draw a realistic, moving trail polyline on a map.
        
        5. PER-SEGMENT CONDITIONS (MANDATORY):
           - Let N = number of coordinates. You MUST output "segment_conditions" as an array of EXACTLY (N - 1) strings.
           - segment_conditions[i] describes the leg FROM coordinates[i] TO coordinates[i+1] (terrain, exposure, steepness, hazard).
           - Each value MUST be EXACTLY one of: "Easy", "Moderate", "Severe" (use "Severe" for hard/exposed/scrambling legs).
           - Be conservative: urban flat paths = Easy; steep or exposed = Severe; everything else = Moderate.
        
        OUTPUT SCHEMA (STRICT JSON ONLY):
        You must output ONLY valid JSON matching this exact schema. Do NOT include markdown formatting blocks like ```json.
        {
            "name": "Title of the Route",
            "description": "A vivid 2-sentence summary of the trail",
            "weather_summary": "Inferred weather conditions based on location and time",
            "recommended_time": "Logical Start/End Time (e.g., 'Tomorrow Morning')",
            "distance": 5.2,
            "difficulty_rating": "Moderate",
            "activity_type": "Cycling",
            "coordinates": [
                { "latitude": 51.5074, "longitude": -0.1278 },
                { "latitude": 51.5075, "longitude": -0.1276 },
                { "latitude": 51.5076, "longitude": -0.1274 }
            ],
            "segment_conditions": ["Easy", "Moderate"]
        }
        """
        
        let requestBody: [String: Any] = [
            "contents": [[ "parts": [["text": systemInstruction]] ]],
            // Forces the AI to output pure JSON without markdown blocks
            "generationConfig": ["response_mime_type": "application/json"]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // DEBUG: Print the payload being sent to Gemini
        print("=== GEMINI REQUEST PAYLOAD ===")
        print("System Instruction:\n\(systemInstruction)\n")
        print("User Prompt: \(userPrompt)")
        print("==============================")
        
        let (data, response) = try await geminiURLSession.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Gemini API Error: \(httpResponse.statusCode)")
            if let rawError = String(data: data, encoding: .utf8) { print("Raw: \(rawError)") }
            throw URLError(.badServerResponse)
        }
        
        // Decode Google's outer wrapper
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let jsonString = geminiResponse.candidates?.first?.content.parts.first?.text else {
            throw URLError(.cannotDecodeContentData)
        }
        
        // Strip markdown backticks if Gemini accidentally includes them
        var cleanedJSONString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedJSONString.hasPrefix("```json") {
            cleanedJSONString = String(cleanedJSONString.dropFirst(7))
        } else if cleanedJSONString.hasPrefix("```") {
            cleanedJSONString = String(cleanedJSONString.dropFirst(3))
        }
        if cleanedJSONString.hasSuffix("```") {
            cleanedJSONString = String(cleanedJSONString.dropLast(3))
        }
        
        guard let routeData = cleanedJSONString.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        // DEBUG: Print the raw JSON received from Gemini
        print("=== GEMINI RAW JSON RESPONSE ===")
        print(cleanedJSONString)
        print("================================")
        
        // Decode your precise JSON schema
        let aiRoute = try JSONDecoder().decode(AIRouteResponse.self, from: routeData)
        
        let enrichedCoordinates = Self.coordinatesWithSegmentConditions(
            from: aiRoute.coordinates,
            segmentConditions: aiRoute.segment_conditions
        )
        
        // Map it directly to our app's TrekRoute blueprint
        return TrekRoute(
            id: UUID().uuidString,
            name: aiRoute.name,
            summary: aiRoute.description,
            distance: aiRoute.distance,
            startLatitude: enrichedCoordinates.first?.latitude ?? 0.0,
            startLongitude: enrichedCoordinates.first?.longitude ?? 0.0,
            weatherSummary: aiRoute.weather_summary,
            estimatedDuration: aiRoute.recommended_time,
            difficultyRating: aiRoute.difficulty_rating,
            activityType: aiRoute.activity_type,
            routeCoordinates: enrichedCoordinates
        )
    }
    
    /// Maps Gemini `segment_conditions` onto each start vertex of a leg. Missing legs stay `nil` → map draws **blue**.
    private static func coordinatesWithSegmentConditions(
        from coords: [CoordinatePoint],
        segmentConditions: [String]?
    ) -> [CoordinatePoint] {
        let n = coords.count
        guard n > 1 else {
            return coords.map { CoordinatePoint(latitude: $0.latitude, longitude: $0.longitude, condition: nil) }
        }
        let segs = segmentConditions ?? []
        return coords.enumerated().map { index, c in
            let cond: String?
            if index < n - 1 {
                cond = index < segs.count ? segs[index] : nil
            } else {
                cond = nil
            }
            return CoordinatePoint(latitude: c.latitude, longitude: c.longitude, condition: cond)
        }
    }
    
    // MARK: - Public route segment conditions (map coloring)
    
    /// Fills per-leg `condition` for map colors. On any failure returns **`route` unchanged** (all-blue polyline).
    func analyzeRouteConditions(for route: TrekRoute) async -> TrekRoute {
        guard let coords = route.routeCoordinates, coords.count > 1 else { return route }
        // Saved / AI routes already persist per-leg `condition` in Firestore — skip extra API calls.
        let noSegmentData = coords.dropLast().allSatisfy { $0.condition == nil }
        if !noSegmentData { return route }
        
        for attempt in 1...3 {
            do {
                return try await performRouteSegmentAnalysis(route: route, coordinates: coords)
            } catch {
                let ns = error as NSError
                print("Gemini segment analysis attempt \(attempt)/3 failed: \(error.localizedDescription) [\(ns.domain) \(ns.code)]")
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        return route
    }
    
    private func performRouteSegmentAnalysis(route: TrekRoute, coordinates coords: [CoordinatePoint]) async throws -> TrekRoute {
        let (sampledCoords, _) = Self.downsampleCoordinates(coords, maxPoints: 18)
        guard sampledCoords.count > 1 else { return route }
        
        let shortSummary = route.summary.count > 450 ? String(route.summary.prefix(450)) + "…" : route.summary
        let coordLines = sampledCoords.enumerated().map { i, p in
            String(format: "%d: %.5f,%.5f", i, p.latitude, p.longitude)
        }.joined(separator: "\n")
        
        let legStats = Self.sampledLegStats(sampledCoords: sampledCoords)
        
        let systemInstruction = """
        You are a professional outdoor route analyst. Classify EACH leg between consecutive sample waypoints for map polyline coloring (Easy = green/blue UI, Moderate = yellow, Severe = red). You must use real judgment — do NOT label every leg "Moderate".

        ROUTE CARD
        - Name: \(route.name)
        - Published distance (km): \(route.distance)
        - Activity type: \(route.activityType ?? "Hiking")
        - Route blurb (use for terrain, setting, hazards): \(shortSummary)
        - Document difficulty tag (metadata only; do NOT copy to every leg): \(route.difficultyRating ?? "none")

        SAMPLE WAYPOINTS (index, lat, lon) — in travel order:
        \(coordLines)

        PER-LEG GEOMETRY (great-circle horizontal distance between consecutive samples; use with place knowledge — short legs in steep areas often mean climb/descent; long legs on flats often easy):
        \(legStats)

        HOW TO SCORE EACH LEG (decide independently for leg i → i+1)
        Use ALL of: (1) route name + blurb, (2) real-world geography at those coordinates, (3) activity type (cycle vs hike vs MTB), (4) leg length and how the path bends, (5) typical surface/exposure for that setting.

        "Easy" — Paved or smooth firm paths, gentle gradients, urban parks, towpaths, forest roads without steep pitch, short connectors on flat ground, low consequence if you slip.

        "Moderate" — Typical hill footpaths, mixed surfaces, steady but non-extreme slopes, forest tracks with some pitch, normal UK/EU trail hiking/cycling where fitness matters but not scrambling.

        "Severe" — Steep or sustained climbs/descents, narrow exposed ridges, scrambling, rocky/rooty technical MTB, cliff or river-edge exposure, bog/tundra/off-trail feel, or any leg you would warn a casual visitor about. Use sparingly but USE IT when the place + blurb + geometry justify it.

        CRITICAL RULES
        - Vary labels across the route when the story of the route varies (flat start → hard climb → easy finish should show that pattern).
        - Never output "Moderate" for every leg unless the entire route is genuinely uniform easy trail AND the blurb confirms it.
        - If unsure between Easy and Moderate, prefer Easy for very short flat-looking legs in tame settings; prefer Severe only when there is a concrete reason (exposure, steepness, technical terrain).
        - Output JSON ONLY, no markdown fences, no commentary.

        SCHEMA (exactly \(sampledCoords.count - 1) strings in the array):
        {"segment_conditions":["Easy","Severe","Moderate",...]}
        Each string MUST be exactly one of: Easy, Moderate, Severe (capital first letter).
        """
        
        let requestBody: [String: Any] = [
            "contents": [[ "parts": [["text": systemInstruction]] ]],
            "generationConfig": [
                "response_mime_type": "application/json",
                "temperature": 0.35
            ] as [String: Any]
        ]
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(segmentAnalysisModel):generateContent?key=\(apiKey)"
        guard let analysisURL = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: analysisURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await geminiURLSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("Gemini segment analysis HTTP \(httpResponse.statusCode): \(body.prefix(500))")
            throw URLError(.badServerResponse)
        }
        
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard var jsonString = geminiResponse.candidates?.first?.content.parts.first?.text else {
            print("Gemini segment analysis: empty candidates (safety filter or stop reason)")
            throw URLError(.cannotDecodeContentData)
        }
        
        jsonString = Self.stripMarkdownJSONFence(jsonString)
        
        guard let payload = jsonString.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        let analysis = try JSONDecoder().decode(RouteConditionAnalysisResponse.self, from: payload)
        let segs = analysis.segment_conditions
        let s = sampledCoords.count
        guard segs.count >= s - 1 else {
            throw URLError(.cannotDecodeContentData)
        }
        
        let mapped = Self.applySampledSegmentConditions(
            fullCoordinates: coords,
            sampledCount: s,
            segmentConditions: Array(segs.prefix(s - 1))
        )
        
        return TrekRoute(
            id: route.id,
            name: route.name,
            summary: route.summary,
            distance: route.distance,
            startLatitude: route.startLatitude,
            startLongitude: route.startLongitude,
            weatherSummary: route.weatherSummary,
            estimatedDuration: route.estimatedDuration,
            difficultyRating: route.difficultyRating,
            activityType: route.activityType,
            routeCoordinates: mapped
        )
    }
    
    private static func stripMarkdownJSONFence(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") {
            s = String(s.dropFirst(7))
        } else if s.hasPrefix("```") {
            s = String(s.dropFirst(3))
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Human-readable leg lengths and bearings so the model can infer gradient context (short legs in mountains often steep).
    private static func sampledLegStats(sampledCoords: [CoordinatePoint]) -> String {
        var lines: [String] = []
        for i in 0..<(sampledCoords.count - 1) {
            let a = sampledCoords[i]
            let b = sampledCoords[i + 1]
            let m = greatCircleMeters(lat1: a.latitude, lon1: a.longitude, lat2: b.latitude, lon2: b.longitude)
            let brg = approximateBearingDegrees(from: a, to: b)
            lines.append(String(format: "Leg %d→%d: ≈%.0f m, bearing ≈%.0f°", i, i + 1, m, brg))
        }
        return lines.joined(separator: "\n")
    }
    
    private static func greatCircleMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthR = 6_371_000.0
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let dφ = (lat2 - lat1) * .pi / 180
        let dλ = (lon2 - lon1) * .pi / 180
        let s1 = sin(dφ / 2)
        let s2 = sin(dλ / 2)
        let h = s1 * s1 + cos(φ1) * cos(φ2) * s2 * s2
        let c = 2 * atan2(sqrt(h), sqrt(1 - h))
        return earthR * c
    }
    
    private static func approximateBearingDegrees(from a: CoordinatePoint, to b: CoordinatePoint) -> Double {
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = atan2(y, x) * 180 / .pi
        return (θ + 360).truncatingRemainder(dividingBy: 360)
    }
    
    /// Returns downsampled coordinates and their original indices (for debugging).
    private static func downsampleCoordinates(_ coords: [CoordinatePoint], maxPoints: Int) -> ([CoordinatePoint], [Int]) {
        let n = coords.count
        guard n > maxPoints else {
            return (coords, Array(0..<n))
        }
        let k = maxPoints
        var indices: [Int] = []
        for i in 0..<k {
            let j = Int(round(Double(i) * Double(n - 1) / Double(k - 1)))
            indices.append(j)
        }
        var unique: [Int] = []
        for idx in indices where !unique.contains(idx) {
            unique.append(idx)
        }
        if unique.last != n - 1 { unique.append(n - 1) }
        let sampled = unique.map { coords[$0] }
        return (sampled, unique)
    }
    
    /// Maps coarse `segment_conditions` (length S-1) onto full polyline (length N). Gaps → `nil` → **blue** on the map.
    private static func applySampledSegmentConditions(
        fullCoordinates coords: [CoordinatePoint],
        sampledCount S: Int,
        segmentConditions: [String]
    ) -> [CoordinatePoint] {
        let n = coords.count
        guard n > 1, S > 1, segmentConditions.count >= S - 1 else { return coords }
        
        return coords.enumerated().map { j, c in
            let cond: String?
            if j < n - 1 {
                let t = Double(j) / Double(n - 1)
                let kk = min(Int(floor(t * Double(S - 1))), S - 2)
                cond = segmentConditions.indices.contains(kk) ? segmentConditions[kk] : nil
            } else {
                cond = nil
            }
            return CoordinatePoint(latitude: c.latitude, longitude: c.longitude, condition: cond)
        }
    }
    
    // MARK: - Checklist Generation Pipeline

    func generateChecklist(for route: TrekRoute) async throws -> [ChecklistItem] {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let difficulty = route.difficultyRating ?? "unknown"
        let activity = route.activityType ?? "Hiking"
        let segmentNote: String
        if let coords = route.routeCoordinates, coords.count > 1,
           coords.dropLast().contains(where: { ($0.condition ?? "").lowercased().contains("severe") }) {
            segmentNote = "At least one leg is tagged Severe/hard — include technical or safety extras."
        } else {
            segmentNote = ""
        }

        let systemInstruction = """
        You are an expert outdoor route planner. Build a preparation checklist tailored to THIS route (not generic).

        ROUTE CONTEXT
        - Name: \(route.name)
        - Distance: \(route.distance) km
        - Difficulty (metadata): \(difficulty)
        - Activity: \(activity)
        - Weather hint: \(route.weatherSummary ?? "unknown")
        - Duration hint: \(route.estimatedDuration ?? "unknown")
        \(segmentNote.isEmpty ? "" : "- Terrain note: \(segmentNote)")

        CATEGORY RULES (important)
        1) ALWAYS use these three exact category names for core items (include at least 2 items spread across them, ideally at least one per category when the route warrants it):
           - "Essentials"
           - "Clothing & Weather"
           - "Navigation & Safety"
        2) If the route is demanding, ADD extra categories with your own short titles (Title Case, 2–5 words), for example:
           - Long (> ~12 km), remote, multi-hour, or hard difficulty → add categories like "Nutrition & Hydration", "Emergency & First Aid", or "Repairs & Tools" as appropriate.
           - Cycling / MTB → consider "Bike & Kit" or similar.
           - Cold/wet/wind from context → reinforce under "Clothing & Weather" and add "Cold Weather" or "Rain Protection" sections if needed.
        3) Do not use more than 8 different category names total. Keep titles concise.

        OUTPUT
        - JSON ONLY, no markdown fences.
        - Either a JSON array of objects, OR a single object with key "items" or "checklist" holding that array.
        - Each object: {"title": "string", "category": "string"} — category is one of the three fixed names OR one of your extra category names.
        - Item count: about 6–10 for easy short routes; up to ~22 for long, hard, or remote routes.
        """

        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": systemInstruction]]]],
            "generationConfig": [
                "response_mime_type": "application/json",
                "temperature": 0.4,
            ] as [String: Any],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await geminiURLSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard var jsonString = geminiResponse.candidates?.first?.content.parts.first?.text else {
            throw URLError(.cannotDecodeContentData)
        }
        jsonString = Self.stripMarkdownJSONFence(jsonString)
        guard let rawData = jsonString.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        let aiItems = try Self.decodeChecklistPayload(from: rawData)
        var validItems: [ChecklistItem] = []
        validItems.reserveCapacity(aiItems.count)
        for aiItem in aiItems {
            let title = aiItem.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 2 else { continue }
            let cat = ChecklistItem.normalizeCategory(aiItem.category)
            validItems.append(ChecklistItem(title: title, category: cat))
        }

        if validItems.isEmpty {
            return Self.fallbackChecklist(for: route)
        }
        return validItems
    }

    private static func decodeChecklistPayload(from rawData: Data) throws -> [AIChecklistResponse] {
        let decoder = JSONDecoder()
        if let arr = try? decoder.decode([AIChecklistResponse].self, from: rawData) {
            return arr
        }
        if let wrapped = try? decoder.decode(AIChecklistEnvelope.self, from: rawData) {
            if let a = wrapped.items, !a.isEmpty { return a }
            if let a = wrapped.checklist, !a.isEmpty { return a }
        }
        throw URLError(.cannotDecodeContentData)
    }

    private static func fallbackChecklist(for route: TrekRoute) -> [ChecklistItem] {
        [
            ChecklistItem(title: "Water for \(String(format: "%.0f", max(0.5, route.distance))) km", category: ChecklistItem.builtInCategories[0]),
            ChecklistItem(title: "Snacks / energy food", category: ChecklistItem.builtInCategories[0]),
            ChecklistItem(title: "Weather-appropriate layers", category: ChecklistItem.builtInCategories[1]),
            ChecklistItem(title: "Map or offline route on phone", category: ChecklistItem.builtInCategories[2]),
            ChecklistItem(title: "Tell someone your plan and return time", category: ChecklistItem.builtInCategories[2]),
        ]
    }
}

// MARK: - Internal Decoding Structures

// Structures to peel back the layers of Google's network response
fileprivate struct GeminiResponse: Codable {
    let candidates: [Candidate]?
}
fileprivate struct Candidate: Codable {
    let content: GeminiContent
}
fileprivate struct GeminiContent: Codable {
    let parts: [Part]
}
fileprivate struct Part: Codable {
    let text: String
}

fileprivate struct AIChecklistResponse: Codable {
    let title: String
    let category: String
}

fileprivate struct AIChecklistEnvelope: Codable {
    let items: [AIChecklistResponse]?
    let checklist: [AIChecklistResponse]?
}

// Structure representing your exact JSON schema output
fileprivate struct AIRouteResponse: Codable {
    let name: String
    let description: String
    let weather_summary: String
    let recommended_time: String
    let distance: Double
    let difficulty_rating: String
    let activity_type: String
    let coordinates: [CoordinatePoint]
    /// Length must be coordinates.count - 1 when present; legs are colored from Gemini.
    let segment_conditions: [String]?
}

fileprivate struct RouteConditionAnalysisResponse: Codable {
    let segment_conditions: [String]
}
