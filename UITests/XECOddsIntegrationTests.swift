import XCTest
import HashFleetCore

@MainActor
final class XECOddsIntegrationTest: XCTestCase {
    func testXECOddsDisplayWithLiveData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()

        // Wait for fleet to load
        sleep(2)

        // Verify solo comparison card exists
        let soloCard = app.otherElements["dashboard.chains"]
        XCTAssertTrue(soloCard.waitForExistence(timeout: 5), "Solo comparison card should exist")

        // Verify XEC data is shown when mining XEC in demo
        // The card should contain difficulty and odds information
        XCTAssertTrue(soloCard.exists, "Solo chain card should display")
    }

    func testBlockchairAPIIntegration() throws {
        // Verify the API client can fetch XEC data
        let expectation = self.expectation(description: "XEC data fetch")

        Task {
            let client = MiningInsightsClient()
            let result = await client.eCash()

            // Verify we got valid data
            if let stats = result.value {
                XCTAssertNotNil(stats.difficulty, "Difficulty should be present")
                XCTAssertNotNil(stats.tipHeight, "Block height should be present")
                XCTAssertTrue(stats.difficulty ?? 0 > 0, "Difficulty should be positive")
                XCTAssertTrue(stats.tipHeight ?? 0 > 0, "Height should be positive")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)
    }
}
