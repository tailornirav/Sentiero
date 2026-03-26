import Foundation

class WeatherService {
    static let shared = WeatherService()

    private var apiKey: String { APIConfig.weatherAPIKey }

    func fetchWeather(latitude: Double, longitude: Double, completion: @escaping (WeatherInfo?) -> Void) {
        
        // 1. Construct the precise URL string, forcing metric units (Celsius)
        let urlString = "https://api.openweathermap.org/data/2.5/weather?lat=\(latitude)&lon=\(longitude)&appid=\(apiKey)&units=metric"
        
        // 2. Safely unwrap the URL to prevent crashes
        guard let url = URL(string: urlString) else {
            print("Weather Service Error: Invalid URL.")
            completion(nil)
            return
        }
        
        // 3. Initiate the background network task
        URLSession.shared.dataTask(with: url) { data, response, error in
            
            // Handle network failures gracefully
            if let error = error {
                print("Weather Network Error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                print("Weather Data Error: No data received.")
                completion(nil)
                return
            }
            
            // 4. Decode off the URLSession callback thread (Sendable models; avoids Swift 6 main-actor Decodable issues).
            do {
                let decodedData = try Self.decodeOpenWeatherResponse(from: data)
                
                // 5. Extract the specific values
                let temp = decodedData.main.temp
                let condition = decodedData.weather.first?.main ?? "Unknown"
                let conditionId = decodedData.weather.first?.id ?? 800
                
                // Map the OpenWeather ID to a native Apple SF Symbol for a clean UI
                let sfSymbol = WeatherService.mapConditionToSFSymbol(conditionId: conditionId)
                
                let weatherInfo = WeatherInfo(temperature: temp, condition: condition, systemIconName: sfSymbol)
                
                completion(weatherInfo)
                
            } catch {
                print("Weather Decoding Error: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }
    
    private static func decodeOpenWeatherResponse(from data: Data) throws -> OpenWeatherResponse {
        try JSONDecoder().decode(OpenWeatherResponse.self, from: data)
    }
    
    // A logical utility function to convert weather codes to Apple's native icons
    private static func mapConditionToSFSymbol(conditionId: Int) -> String {
        switch conditionId {
        case 200...232: return "cloud.bolt.rain.fill" // Thunderstorm
        case 300...321: return "cloud.drizzle.fill"   // Drizzle
        case 500...531: return "cloud.rain.fill"      // Rain
        case 600...622: return "snow"                 // Snow
        case 701...781: return "cloud.fog.fill"       // Atmosphere (Fog/Mist)
        case 800:       return "sun.max.fill"         // Clear
        case 801...804: return "cloud.fill"           // Clouds
        default:        return "cloud.sun.fill"       // Fallback
        }
    }
}
