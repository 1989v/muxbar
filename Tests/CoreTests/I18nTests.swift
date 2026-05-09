import XCTest
@testable import Core

final class I18nTests: XCTestCase {
    /// 양쪽 .lproj/Localizable.strings 의 키 set 이 정확히 일치해야 함.
    func test_allKeys_existInBothLprojs() throws {
        let bundle = Bundle.module

        let enKeys = try keysFromLproj(in: bundle, lang: "en")
        let koKeys = try keysFromLproj(in: bundle, lang: "ko")

        let onlyInEn = enKeys.subtracting(koKeys)
        let onlyInKo = koKeys.subtracting(enKeys)

        XCTAssertTrue(onlyInEn.isEmpty, "ko.lproj 누락 키: \(onlyInEn.sorted())")
        XCTAssertTrue(onlyInKo.isEmpty, "en.lproj 누락 키: \(onlyInKo.sorted())")
    }

    func test_lookup_returnsNonEmptyForKnownKey() {
        XCTAssertFalse(L.menuKeepAwake.isEmpty)
        XCTAssertFalse(L.closedLidStateOff.isEmpty)
    }

    /// `closedLid.state.onTimer` 의 %@ format substitution 동작.
    func test_closedLidStateOnTimer_substitutesPlaceholder() {
        let s = L.closedLidStateOnTimer("3:47:12")
        XCTAssertTrue(s.contains("3:47:12"), "결과: \(s)")
    }

    // MARK: LocaleService tests

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "muxbar.test.locale.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @MainActor
    func test_languagePreference_defaultsToAuto() {
        let svc = LocaleService(defaults: makeIsolatedDefaults())
        XCTAssertEqual(svc.preference, .auto)
    }

    @MainActor
    func test_languagePreference_persists() {
        let defaults = makeIsolatedDefaults()
        let svc1 = LocaleService(defaults: defaults)
        svc1.preference = .ko

        let svc2 = LocaleService(defaults: defaults)
        XCTAssertEqual(svc2.preference, .ko)
    }

    @MainActor
    func test_applyAtLaunch_auto_removesAppleLanguagesKey() {
        let defaults = makeIsolatedDefaults()
        defaults.set(["en"], forKey: "AppleLanguages")
        let svc = LocaleService(defaults: defaults)
        svc.preference = .auto
        svc.applyAtLaunch()
        XCTAssertNil(defaults.array(forKey: "AppleLanguages"))
    }

    @MainActor
    func test_applyAtLaunch_en_setsEnglishOverride() {
        let defaults = makeIsolatedDefaults()
        let svc = LocaleService(defaults: defaults)
        svc.preference = .en
        svc.applyAtLaunch()
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["en"])
    }

    @MainActor
    func test_applyAtLaunch_ko_setsKoreanOverride() {
        let defaults = makeIsolatedDefaults()
        let svc = LocaleService(defaults: defaults)
        svc.preference = .ko
        svc.applyAtLaunch()
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["ko"])
    }

    // MARK: helpers

    private func keysFromLproj(in bundle: Bundle, lang: String) throws -> Set<String> {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "strings",
                                    subdirectory: nil, localization: lang)
        else {
            XCTFail("\(lang).lproj/Localizable.strings 못 찾음")
            return []
        }
        guard let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            XCTFail("\(lang).lproj/Localizable.strings parse 실패")
            return []
        }
        return Set(dict.keys)
    }
}
