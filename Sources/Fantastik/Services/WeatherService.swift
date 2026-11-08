import SwiftUI
import CoreLocation

/// Forecast via Open-Meteo (no API key) at the device's location.
@MainActor @Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    struct Day { let symbol: String; let high: Int; let low: Int }

    private(set) var days: [Date: Day] = [:]
    private(set) var location: CLLocation?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastFetch: Date?

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "showWeather") as? Bool ?? true }
    var useFahrenheit: Bool {
        if let v = UserDefaults.standard.object(forKey: "useFahrenheit") as? Bool { return v }
        return Locale.current.measurementSystem == .us
    }

    func start() {
        guard isEnabled else { return }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.requestLocation()
    }

    func weather(for day: Date) -> Day? { isEnabled ? days[day.startOfDay] : nil }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.location = loc
            await self.fetch(loc)
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let s = manager.authorizationStatus
            if s == .authorizedAlways || s == .authorized { manager.requestLocation() }
        }
    }

    private func fetch(_ loc: CLLocation) async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 1800, !days.isEmpty { return }
        let f = useFahrenheit
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(loc.coordinate.latitude)&longitude=\(loc.coordinate.longitude)&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=14&temperature_unit=\(f ? "fahrenheit" : "celsius")"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = json["daily"] as? [String: Any],
              let times = daily["time"] as? [String], let codes = daily["weather_code"] as? [Int],
              let highs = daily["temperature_2m_max"] as? [Double], let lows = daily["temperature_2m_min"] as? [Double]
        else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var result: [Date: Day] = [:]
        for i in times.indices where i < codes.count && i < highs.count && i < lows.count {
            if let d = df.date(from: times[i]) {
                result[d.startOfDay] = Day(symbol: Self.symbol(codes[i]), high: Int(highs[i].rounded()), low: Int(lows[i].rounded()))
            }
        }
        days = result
        lastFetch = Date()
    }

    static func symbol(_ code: Int) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 80...82: "cloud.heavyrain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

struct WeatherBadge: View {
    let day: Date
    var showLow = false
    private let service = WeatherService.shared

    var body: some View {
        if let w = service.weather(for: day) {
            HStack(spacing: 3) {
                Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 11))
                Text("\(w.high)°").font(.system(size: 11, weight: .medium)).monospacedDigit()
                if showLow { Text("\(w.low)°").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit() }
            }
            .foregroundStyle(.secondary)
        }
    }
}
