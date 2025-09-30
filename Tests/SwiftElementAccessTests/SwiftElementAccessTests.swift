import XCTest
@testable import SwiftElementAccess

final class SwiftElementAccessTests: XCTestCase {
    func testExample() async throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        // XCTAssertEqual(SwiftElementAccess().text, "Hello, World!")

        let img = await AXUIElement.captureImage(screenBounds: NSRect.infinite, path: "screenshot-infinite.png")

    }
}
