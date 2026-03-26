import Foundation

/// Loads API keys from `Secrets.plist` in the app bundle (not committed — copy from `Secrets.example.plist`).
enum APIConfig {
    private static let secretsPlistName = "Secrets"

    private static let plistStrings: [String: String] = {
        guard let url = Bundle.main.url(forResource: secretsPlistName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return [:]
        }
        var out: [String: String] = [:]
        for (key, value) in root {
            if let s = value as? String {
                out[key] = s
            }
        }
        return out
    }()

    static var geminiAPIKey: String {
        plistStrings["GeminiAPIKey"] ?? ""
    }

    static var weatherAPIKey: String {
        plistStrings["WeatherAPIKey"] ?? ""
    }
}
