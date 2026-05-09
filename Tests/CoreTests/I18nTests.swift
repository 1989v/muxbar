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
