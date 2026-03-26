import Foundation

struct WalkCompletionSummary: Identifiable {
    let id = UUID()
    let routeName: String
    let routeDistanceKm: Double
    let kind: Kind

    enum Kind {
        case reachedDestination
        case completedLoop
        case endedEarly
    }

    var title: String {
        switch kind {
        case .reachedDestination:
            return "You reached the finish"
        case .completedLoop:
            return "Loop complete"
        case .endedEarly:
            return "Walk ended"
        }
    }

    var message: String {
        switch kind {
        case .reachedDestination:
            return "You’re at the end of \(routeName). Great job completing the route."
        case .completedLoop:
            return "You’re back at the start — you’ve closed the loop on \(routeName)."
        case .endedEarly:
            return "You chose to end \(routeName) now. Continue below to save it to your profile."
        }
    }
}
