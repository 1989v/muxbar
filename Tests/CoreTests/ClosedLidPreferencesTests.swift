import XCTest
@testable import Core

@MainActor
final class ClosedLidPreferencesTests: XCTestCase {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "muxbar.test.closedLidPrefs.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func test_default_caffeinateCommand_isMinusIs() {
        let prefs = ClosedLidPreferences(defaults: makeIsolatedDefaults())
        XCTAssertEqual(prefs.caffeinateCommand(), "caffeinate -is")
    }

    func test_keepDisplayAwake_addsD() {
        let prefs = ClosedLidPreferences(defaults: makeIsolatedDefaults())
        prefs.keepDisplayAwake = true
        XCTAssertEqual(prefs.caffeinateCommand(), "caffeinate -isd")
    }

    func test_preventScreenSaver_addsU() {
        let prefs = ClosedLidPreferences(defaults: makeIsolatedDefaults())
        prefs.preventScreenSaver = true
        XCTAssertEqual(prefs.caffeinateCommand(), "caffeinate -isu")
    }

    func test_bothFlags_addsDU() {
        let prefs = ClosedLidPreferences(defaults: makeIsolatedDefaults())
        prefs.keepDisplayAwake = true
        prefs.preventScreenSaver = true
        XCTAssertEqual(prefs.caffeinateCommand(), "caffeinate -isdu")
    }

    func test_userDefaultsPersistence() {
        let defaults = makeIsolatedDefaults()
        let prefs1 = ClosedLidPreferences(defaults: defaults)
        prefs1.keepDisplayAwake = true
        prefs1.preventScreenSaver = true

        let prefs2 = ClosedLidPreferences(defaults: defaults)
        XCTAssertTrue(prefs2.keepDisplayAwake)
        XCTAssertTrue(prefs2.preventScreenSaver)
    }
}
