import XCTest
@testable import HUDDL

final class ValidationTests: XCTestCase {
    func testUsernameRules() {
        XCTAssertEqual(Validation.username(""), "Choose a username")
        XCTAssertEqual(Validation.username("edna alas-as!"), "Spaces aren't allowed in usernames")
        XCTAssertNotNil(Validation.username("edna!"))
        XCTAssertNil(Validation.username("ednaalas-as"))
    }
    func testEmailPasswordConfirm() {
        XCTAssertEqual(Validation.email("bad"), "Enter a valid email address")
        XCTAssertNil(Validation.email("edna@huddl.test"))
        XCTAssertEqual(Validation.password("short"), "Use at least 8 characters")
        XCTAssertNotNil(Validation.password("longenough", requireNumber: true))
        XCTAssertNil(Validation.password("longenough1", requireNumber: true))
        XCTAssertEqual(Validation.confirm("abcdefgh", "abcdefgx"), "Passwords don't match")
    }
    func testGeoRadius() {
        let lucena = Geo.lucena
        let mseuf = (13.9446, 121.6182)
        XCTAssertLessThan(Geo.distanceKm(lucena.latitude, lucena.longitude, mseuf.0, mseuf.1), 10)
        XCTAssertEqual(Geo.geohash(lat: 13.9414, lon: 121.6234, precision: 4).count, 4)
        XCTAssertTrue(Geo.coveringPrefixes(lat: lucena.latitude, lon: lucena.longitude).contains(String(lucena.geohash.prefix(4))))
    }
    func testInitials() {
        XCTAssertEqual(AvatarView.initials(for: "Edna Alas-as"), "EA")
        XCTAssertEqual(AvatarView.initials(for: "Althea Trisha Mae Aringo"), "AA")
    }
}
