import Foundation

/// A North American thoroughbred track: Equibase code, name, state or province, and where it is
/// (straight-line location, for the 200-mile race search).
struct Track: Hashable, Identifiable {
    let code: String
    let name: String
    let state: String
    let lat: Double
    let lon: Double

    var id: String { code }

    var isCanadian: Bool { ["ON", "BC", "AB", "MB"].contains(state) }

    static let all: [Track] = [
        Track(code: "AQU", name: "Aqueduct", state: "NY", lat: 40.672, lon: -73.830),
        Track(code: "BEL", name: "Belmont Park", state: "NY", lat: 40.715, lon: -73.722),
        Track(code: "SAR", name: "Saratoga", state: "NY", lat: 43.072, lon: -73.770),
        Track(code: "FL", name: "Finger Lakes", state: "NY", lat: 42.958, lon: -77.428),
        Track(code: "LRL", name: "Laurel Park", state: "MD", lat: 39.103, lon: -76.832),
        Track(code: "PIM", name: "Pimlico", state: "MD", lat: 39.353, lon: -76.668),
        Track(code: "TIM", name: "Timonium", state: "MD", lat: 39.448, lon: -76.630),
        Track(code: "CT", name: "Charles Town", state: "WV", lat: 39.291, lon: -77.853),
        Track(code: "MNR", name: "Mountaineer", state: "WV", lat: 40.513, lon: -80.596),
        Track(code: "PEN", name: "Penn National", state: "PA", lat: 40.402, lon: -76.665),
        Track(code: "PRX", name: "Parx Racing", state: "PA", lat: 40.124, lon: -74.952),
        Track(code: "PID", name: "Presque Isle Downs", state: "PA", lat: 42.071, lon: -80.002),
        Track(code: "DEL", name: "Delaware Park", state: "DE", lat: 39.698, lon: -75.668),
        Track(code: "MTH", name: "Monmouth Park", state: "NJ", lat: 40.316, lon: -74.002),
        Track(code: "CNL", name: "Colonial Downs", state: "VA", lat: 37.548, lon: -77.088),
        Track(code: "SHD", name: "Shenandoah Downs", state: "VA", lat: 38.881, lon: -78.506),
        Track(code: "KEE", name: "Keeneland", state: "KY", lat: 38.046, lon: -84.607),
        Track(code: "CD", name: "Churchill Downs", state: "KY", lat: 38.203, lon: -85.770),
        Track(code: "ELP", name: "Ellis Park", state: "KY", lat: 37.910, lon: -87.548),
        Track(code: "KD", name: "Kentucky Downs", state: "KY", lat: 36.633, lon: -86.570),
        Track(code: "TP", name: "Turfway Park", state: "KY", lat: 39.005, lon: -84.638),
        Track(code: "TDN", name: "Thistledown", state: "OH", lat: 41.412, lon: -81.523),
        Track(code: "BTP", name: "Belterra Park", state: "OH", lat: 39.071, lon: -84.401),
        Track(code: "MVR", name: "Mahoning Valley", state: "OH", lat: 41.081, lon: -80.722),
        Track(code: "IND", name: "Horseshoe Indianapolis", state: "IN", lat: 39.522, lon: -85.747),
        Track(code: "HAW", name: "Hawthorne", state: "IL", lat: 41.817, lon: -87.743),
        Track(code: "FAN", name: "FanDuel Sportsbook & Horse Racing", state: "IL", lat: 38.660, lon: -90.023),
        Track(code: "CBY", name: "Canterbury Park", state: "MN", lat: 44.775, lon: -93.483),
        Track(code: "PRM", name: "Prairie Meadows", state: "IA", lat: 41.651, lon: -93.476),
        Track(code: "FON", name: "Fonner Park", state: "NE", lat: 40.913, lon: -98.352),
        Track(code: "ARP", name: "Arapahoe Park", state: "CO", lat: 39.633, lon: -104.712),
        Track(code: "RP", name: "Remington Park", state: "OK", lat: 35.531, lon: -97.475),
        Track(code: "WRD", name: "Will Rogers Downs", state: "OK", lat: 36.325, lon: -95.584),
        Track(code: "OP", name: "Oaklawn Park", state: "AR", lat: 34.484, lon: -93.058),
        Track(code: "LS", name: "Lone Star Park", state: "TX", lat: 32.746, lon: -96.984),
        Track(code: "HOU", name: "Sam Houston", state: "TX", lat: 29.932, lon: -95.517),
        Track(code: "RET", name: "Retama Park", state: "TX", lat: 29.583, lon: -98.271),
        Track(code: "GIL", name: "Gillespie County", state: "TX", lat: 30.264, lon: -98.872),
        Track(code: "DED", name: "Delta Downs", state: "LA", lat: 30.236, lon: -93.574),
        Track(code: "EVD", name: "Evangeline Downs", state: "LA", lat: 30.538, lon: -92.061),
        Track(code: "LAD", name: "Louisiana Downs", state: "LA", lat: 32.520, lon: -93.637),
        Track(code: "FG", name: "Fair Grounds", state: "LA", lat: 29.982, lon: -90.080),
        Track(code: "GP", name: "Gulfstream Park", state: "FL", lat: 25.979, lon: -80.138),
        Track(code: "GPW", name: "Gulfstream Park West", state: "FL", lat: 25.955, lon: -80.240),
        Track(code: "TAM", name: "Tampa Bay Downs", state: "FL", lat: 28.059, lon: -82.645),
        Track(code: "TUP", name: "Turf Paradise", state: "AZ", lat: 33.675, lon: -112.100),
        Track(code: "AZD", name: "Arizona Downs", state: "AZ", lat: 34.598, lon: -112.375),
        Track(code: "ZIA", name: "Zia Park", state: "NM", lat: 32.716, lon: -103.120),
        Track(code: "SUN", name: "Sunland Park", state: "NM", lat: 31.800, lon: -106.556),
        Track(code: "RUI", name: "Ruidoso Downs", state: "NM", lat: 33.335, lon: -105.643),
        Track(code: "ALB", name: "Albuquerque", state: "NM", lat: 35.070, lon: -106.578),
        Track(code: "SA", name: "Santa Anita", state: "CA", lat: 34.140, lon: -118.044),
        Track(code: "DMR", name: "Del Mar", state: "CA", lat: 32.975, lon: -117.262),
        Track(code: "LA", name: "Los Alamitos", state: "CA", lat: 33.802, lon: -118.051),
        Track(code: "PLN", name: "Pleasanton", state: "CA", lat: 37.665, lon: -121.878),
        Track(code: "FNO", name: "Fresno", state: "CA", lat: 36.727, lon: -119.773),
        Track(code: "FER", name: "Ferndale", state: "CA", lat: 40.578, lon: -124.260),
        Track(code: "EMD", name: "Emerald Downs", state: "WA", lat: 47.315, lon: -122.229),
        Track(code: "WO", name: "Woodbine", state: "ON", lat: 43.717, lon: -79.603),
        Track(code: "FE", name: "Fort Erie", state: "ON", lat: 42.917, lon: -78.937),
        Track(code: "HST", name: "Hastings", state: "BC", lat: 49.283, lon: -123.036),
        Track(code: "CMR", name: "Century Mile", state: "AB", lat: 53.317, lon: -113.555),
        Track(code: "ASD", name: "Assiniboia Downs", state: "MB", lat: 49.897, lon: -97.339),
    ]

    /// Tracks sorted by name, for pickers.
    static let byName: [Track] = all.sorted { $0.name < $1.name }

    private static let byCode: [String: Track] = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    /// A track by Equibase code ("DED") or name ("Delta Downs"), or nil.
    static func find(_ codeOrName: String?) -> Track? {
        guard let raw = codeOrName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let track = byCode[raw.uppercased()] { return track }
        let low = raw.lowercased()
        if let exact = all.first(where: { $0.name.lowercased() == low }) { return exact }
        return all.first { low.contains($0.name.lowercased()) || $0.name.lowercased().contains(low) }
    }

    /// Straight-line miles between two tracks.
    static func miles(_ a: Track, _ b: Track) -> Double {
        let r = 3958.8
        func rad(_ d: Double) -> Double { d * .pi / 180 }
        let dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon)
        let h = pow(sin(dLat / 2), 2) + cos(rad(a.lat)) * cos(rad(b.lat)) * pow(sin(dLon / 2), 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// "Equibase code=Name" pairs, for the chart reader.
    static var codeList: String { all.map { "\($0.name)=\($0.code)" }.joined(separator: ", ") }
}
