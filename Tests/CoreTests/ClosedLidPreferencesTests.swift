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

    func test_alsoStopKeepAwakeOnEnd_persists() {
        let defaults = makeIsolatedDefaults()
        let prefs1 = ClosedLidPreferences(defaults: defaults)
        XCTAssertFalse(prefs1.alsoStopKeepAwakeOnEnd)  // default false
        prefs1.alsoStopKeepAwakeOnEnd = true

        let prefs2 = ClosedLidPreferences(defaults: defaults)
        XCTAssertTrue(prefs2.alsoStopKeepAwakeOnEnd)
    }

    func test_lastCustomMinutes_defaultsTo90_andPersists() {
        let defaults = makeIsolatedDefaults()
        let prefs1 = ClosedLidPreferences(defaults: defaults)
        XCTAssertEqual(prefs1.lastCustomMinutes, 90)  // default
        prefs1.lastCustomMinutes = 45

        let prefs2 = ClosedLidPreferences(defaults: defaults)
        XCTAssertEqual(prefs2.lastCustomMinutes, 45)
    }
}
