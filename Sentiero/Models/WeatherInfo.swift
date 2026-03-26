//
//  WeatherInfo.swift
//  Sentiero
//
//  Created by Nirav Tailor on 26/02/2026.
//


import Foundation

// 1. The structural representation of the exact data we want to keep
struct WeatherInfo {
    let temperature: Double
    let condition: String
    let systemIconName: String
}

// 2. The decodable structures that perfectly mirror OpenWeather's JSON response
struct OpenWeatherResponse: Codable, Sendable {
    let main: MainWeatherData
    let weather: [WeatherConditionData]
}

struct MainWeatherData: Codable, Sendable {
    let temp: Double
}

struct WeatherConditionData: Codable, Sendable {
    let main: String
    let description: String
    let id: Int // OpenWeather uses specific IDs for conditions (e.g., 800 is Clear)
}
