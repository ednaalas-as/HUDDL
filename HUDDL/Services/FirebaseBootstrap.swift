import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseFunctions

/// Configures Firebase.
/// - If `GoogleService-Info.plist` is bundled, the real project is used.
/// - Otherwise (and always when `HUDDL_USE_EMULATORS=1`), the app talks to the local Firebase Emulator Suite
///   under the offline demo project `demo-huddl`. No production credentials live in the client.
enum FirebaseBootstrap {
    static let emulatorHost: String = ProcessInfo.processInfo.environment["HUDDL_EMULATOR_HOST"] ?? "127.0.0.1"
    private(set) static var usingEmulators = false

    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        let plist = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
        let forceEmulators = ProcessInfo.processInfo.environment["HUDDL_USE_EMULATORS"] == "1"

        if let plist, let options = FirebaseOptions(contentsOfFile: plist) {
            FirebaseApp.configure(options: options)
            usingEmulators = forceEmulators
        } else {
            let options = FirebaseOptions(googleAppID: "1:000000000000:ios:0000000000000000", gcmSenderID: "000000000000")
            options.projectID = "demo-huddl"
            options.apiKey = "AIzaSyD3m0-Loca1Emu1at0r-0n1y-N0tReal00" // dummy, correctly-shaped key for the offline demo project (not a credential)
            options.storageBucket = "demo-huddl.appspot.com"
            FirebaseApp.configure(options: options)
            usingEmulators = true
        }

        if usingEmulators {
            Auth.auth().useEmulator(withHost: emulatorHost, port: 9099)
            let settings = Firestore.firestore().settings
            settings.host = "\(emulatorHost):8080"
            settings.isSSLEnabled = false
            settings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = settings
            Storage.storage().useEmulator(withHost: emulatorHost, port: 9199)
            Functions.functions(region: FunctionsClient.region).useEmulator(withHost: emulatorHost, port: 5001)
        } else {
            let settings = Firestore.firestore().settings
            settings.cacheSettings = PersistentCacheSettings()
            Firestore.firestore().settings = settings
        }
    }
}

// MARK: - Geohash (for the 10 km radius and "Nearest" sort)

enum Geo {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    static func geohash(lat: Double, lon: Double, precision: Int = 9) -> String {
        var latR = (-90.0, 90.0), lonR = (-180.0, 180.0)
        var hash = "", bit = 0, ch = 0, even = true
        while hash.count < precision {
            if even {
                let mid = (lonR.0 + lonR.1) / 2
                if lon >= mid { ch |= 1 << (4 - bit); lonR.0 = mid } else { lonR.1 = mid }
            } else {
                let mid = (latR.0 + latR.1) / 2
                if lat >= mid { ch |= 1 << (4 - bit); latR.0 = mid } else { latR.1 = mid }
            }
            even.toggle()
            if bit < 4 { bit += 1 } else { hash.append(base32[ch]); bit = 0; ch = 0 }
        }
        return hash
    }

    /// Great-circle distance in kilometres.
    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180, dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    /// 4-char geohash cells are ~39×19 km, so the cell plus its 8 neighbours always covers a 10 km radius.
    static func coveringPrefixes(lat: Double, lon: Double) -> [String] {
        let dLat = 0.18, dLon = 0.36
        var set = Set<String>()
        for a in [-dLat, 0, dLat] { for b in [-dLon, 0, dLon] { set.insert(geohash(lat: lat + a, lon: lon + b, precision: 4)) } }
        return Array(set)
    }

    static func format(km: Double) -> String { km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km" }

    /// Default home area used in the design (Lucena City, Quezon).
    static let lucena = HomeArea(name: "Lucena City", latitude: 13.9414, longitude: 121.6234,
                                 geohash: geohash(lat: 13.9414, lon: 121.6234))
}
