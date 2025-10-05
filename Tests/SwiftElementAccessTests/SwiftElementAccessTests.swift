import XCTest
@testable import SwiftElementAccess

final class SwiftElementAccessTests: XCTestCase {
    func testExample() async throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        // XCTAssertEqual(SwiftElementAccess().text, "Hello, World!")

        // let img = await AXUIElement.captureImage(screenBounds: NSRect.infinite, path: "screenshot-infinite.png")

        let app = AXUIElement.fromBundleIdentifier("com.tencent.xinWeChat").first!
        print("window:", app.windows.first!.frame!)

        let _ = await app.windows.first!.take_screenshot(path: "window.png")

    }
}
