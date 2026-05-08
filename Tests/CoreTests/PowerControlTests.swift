import XCTest
@testable import Core

final class PowerControlTests: XCTestCase {
    func test_buildScript_disable_true_emitsValueOne() {
        XCTAssertEqual(
            PowerControl.buildScript(disable: true),
            #"do shell script "/usr/bin/pmset -a disablesleep 1" with administrator privileges"#
        )
    }

    func test_buildScript_disable_false_emitsValueZero() {
        XCTAssertEqual(
            PowerControl.buildScript(disable: false),
            #"do shell script "/usr/bin/pmset -a disablesleep 0" with administrator privileges"#
        )
    }

    func test_mapError_userCancelledCode_returnsUserCancelled() {
        let dict: NSDictionary = [
            NSAppleScript.errorNumber: NSNumber(value: -128),
            NSAppleScript.errorMessage: "User canceled."
        ]
        XCTAssertEqual(PowerControl.mapError(dict), .userCancelled)
    }

    func test_mapError_otherCode_returnsScriptFailedWithMessage() {
        let dict: NSDictionary = [
            NSAppleScript.errorNumber: NSNumber(value: -1),
            NSAppleScript.errorMessage: "boom"
        ]
        XCTAssertEqual(PowerControl.mapError(dict), .scriptFailed("boom"))
    }
}
