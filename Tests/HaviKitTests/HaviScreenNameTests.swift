import XCTest
@testable import HaviKit

/// Best-effort screen-name auto-detection (phone-QA finding 4). Pure over a
/// view-controller type name, so it runs on the host with no Simulator: generic
/// container/hosting controllers carry no useful name and yield `nil` (the caller
/// falls through to "unknown"); a real controller yields its module-stripped,
/// generic-stripped class name.
final class HaviScreenNameTests: XCTestCase {
    func testRealControllerYieldsModuleStrippedName() {
        XCTAssertEqual(HaviScreenName.screen(forControllerType: "Lesewerkstatt.ReaderViewController"), "ReaderViewController")
        XCTAssertEqual(HaviScreenName.screen(forControllerType: "SettingsScreenController"), "SettingsScreenController")
    }

    func testGenericContainersYieldNil() {
        XCTAssertNil(HaviScreenName.screen(forControllerType: "UIHostingController<AnyView>"))
        XCTAssertNil(HaviScreenName.screen(forControllerType: "SwiftUI.UIHostingController<ModifiedContent<RootView, HaviOverlayModifier>>"))
        XCTAssertNil(HaviScreenName.screen(forControllerType: "UINavigationController"))
        XCTAssertNil(HaviScreenName.screen(forControllerType: "UITabBarController"))
        XCTAssertNil(HaviScreenName.screen(forControllerType: "UIViewController"))
    }

    func testGenericArgumentsAreStrippedForRealControllers() {
        XCTAssertEqual(HaviScreenName.screen(forControllerType: "MyApp.CardViewController<Word>"), "CardViewController")
    }

    func testEmptyIsNil() {
        XCTAssertNil(HaviScreenName.screen(forControllerType: ""))
    }
}
