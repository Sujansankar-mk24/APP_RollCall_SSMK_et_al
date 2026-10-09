//
//  RescueSightUITests.swift
//  RescueSightUITests
//
//  End-to-end tests that tap through the real app, exactly like a person
//  would, against the real backend.
//
//  Before running them, start the backend with fresh demo data:
//      cd backend
//      source .venv/bin/activate
//      python -m scripts.reset_demo
//      uvicorn app.main:app
//  Then in Xcode: Product > Test (⌘U).
//

import CoreLocation
import XCTest

final class RescueSightUITests: XCTestCase {

    /// Right next to the demo grass fire on FM 1570, south of Greenville.
    private let besideGreenvilleFire = CLLocation(latitude: 33.0712, longitude: -96.1043)

    override func setUp() {
        continueAfterFailure = false
    }

    /// Keep a picture of the screen after every test, so a failure is easy to understand.
    override func tearDown() async throws {
        let picture = await MainActor.run { XCUIScreen.main.screenshot() }
        let attachment = XCTAttachment(screenshot: picture)
        attachment.name = "Final screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Map

    @MainActor
    func testZoomButtonsWork() {
        let app = launchApp()
        let zoomIn = app.buttons["zoomInButton"]
        let zoomOut = app.buttons["zoomOutButton"]
        XCTAssertTrue(zoomIn.isHittable && zoomOut.isHittable)
        zoomIn.tap()
        zoomIn.tap()
        zoomOut.tap()
        // Still on the map, with the main button available.
        XCTAssertTrue(app.buttons["reportIncidentButton"].isHittable)
    }

    // MARK: - Incidents tab

    @MainActor
    func testIncidentsTabShowsKPIsAndAPrioritySortedList() {
        let app = launchApp()
        app.tabBars.buttons["Incidents"].tap()

        // Four key numbers. In the demo data, 4 incidents are active and 3 are responding.
        let active = app.descendants(matching: .any)["kpi_active"]
        XCTAssertTrue(active.waitForExistence(timeout: 15), "The KPI cards never appeared")
        XCTAssertTrue(active.label.hasPrefix("Active incidents: 4"), "Unexpected: \(active.label)")
        XCTAssertTrue(active.label.contains("3 responding"))
        for id in ["kpi_people", "kpi_unverified", "kpi_response"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].exists, "Missing \(id)")
        }

        // Highest priority first: the Greenville grass fire (score 100, newest report).
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'incidentRow_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.element(boundBy: 0).identifier, "incidentRow_1")

        // The Resolved filter shows only the 3 resolved incidents.
        app.buttons["Resolved (3)"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["incidentRow_2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["incidentRow_1"].exists)
        app.buttons["Open (7)"].tap()

        // Tapping a row opens the same detail sheet as on the map.
        let first = app.descendants(matching: .any)["incidentRow_1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(app.staticTexts["AI analysis"].waitForExistence(timeout: 10), "The detail sheet didn't open")
    }

    // MARK: - Reporting

    @MainActor
    func testReportingAFireBesideAnExistingFireMergesIntoIt() {
        let app = launchApp()
        app.buttons["reportIncidentButton"].tap()

        // The pin goes to the phone's location; wait for the street name.
        waitForPlaceName(in: app, containing: "Greenville")

        app.buttons["Fire"].firstMatch.tap()
        let send = app.buttons["sendReportButton"]
        XCTAssertTrue(send.isEnabled)
        send.tap()

        let toast = app.descendants(matching: .any)["reportSentToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 20), "The report confirmation never appeared")
        XCTAssertTrue(toast.label.contains("Added to existing incident"), "Expected a merge, got: \(toast.label)")
    }

    @MainActor
    func testSearchingAnAddressMovesThePin() {
        let app = launchApp()
        app.buttons["reportIncidentButton"].tap()

        let search = app.textFields["addressSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        app.swipeUp()  // the search box starts below the type tiles
        search.tap()
        search.typeText("Sherman, TX")

        // Pick the city itself, not "Sherman St" in some other town.
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sherman, TX'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15), "No address suggestions appeared")
        suggestion.tap()

        waitForPlaceName(in: app, containing: "Sherman, TX")
    }

    @MainActor
    func testReportWithALibraryPhotoGetsAnAIResult() throws {
        let app = launchApp()
        app.buttons["reportIncidentButton"].tap()
        waitForPlaceName(in: app, containing: "Greenville")
        app.buttons["Fire"].firstMatch.tap()

        app.swipeUp()
        app.swipeUp()
        app.buttons["Choose from library"].tap()
        // The photo picker is part of iOS. Its pictures are "images" labeled
        // "Photo, <date>" (videos say "Video, ..."); pick the first photo.
        let photo = app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info' AND label BEGINSWITH 'Photo,'")).firstMatch
        guard photo.waitForExistence(timeout: 15) else {
            throw XCTSkip("No photos found in the picker. Add one with: xcrun simctl addmedia booted <photo.jpg>")
        }
        photo.tap()
        // The picker closes by itself once a photo is chosen.
        XCTAssertTrue(app.buttons["Choose from library"].waitForNonExistence(timeout: 10) || !photo.exists,
                      "The photo picker stayed open after tapping a photo")

        XCTAssertTrue(app.buttons["Remove"].waitForExistence(timeout: 15), "The chosen photo didn't load")
        app.buttons["sendReportButton"].tap()

        let toast = app.descendants(matching: .any)["reportSentToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 20))
        // The confirmation follows the AI until it has an answer.
        let finished = NSPredicate(format: "label CONTAINS 'AI found' OR label CONTAINS 'AI didn' OR label CONTAINS 'shortly'")
        expectation(for: finished, evaluatedWith: toast)
        waitForExpectations(timeout: 30)
    }

    // MARK: - Drone feed

    @MainActor
    func testDroneFeedGoesLiveWithAICounts() {
        // Open the Greenville grass fire's sheet at full height.
        let app = launchApp(arguments: ["-RSSelectIncident", "1", "-RSLargeSheet", "YES"])

        let launch = app.buttons["launchDroneFeedButton"]
        XCTAssertTrue(launch.waitForExistence(timeout: 15))
        scrollUntilHittable(launch, in: app)
        launch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["liveDroneFrame"].waitForExistence(timeout: 15),
                      "The live drone picture never appeared")
        XCTAssertTrue(app.staticTexts["People in view"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["May be down"].exists)

        let stop = app.buttons["stopDroneFeedButton"]
        scrollUntilHittable(stop, in: app)
        stop.tap()
        XCTAssertTrue(launch.waitForExistence(timeout: 15), "The feed didn't stop")
    }

    // MARK: - Helpers

    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.location = XCUILocation(location: besideGreenvilleFire)
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()

        let reportButton = app.buttons["reportIncidentButton"]
        if !reportButton.waitForExistence(timeout: 20) {
            XCTFail("The map didn't load. Is the backend running? (uvicorn app.main:app)")
        }
        return app
    }

    @MainActor
    private func waitForPlaceName(in app: XCUIApplication, containing text: String) {
        let place = app.staticTexts["pinPlaceName"]
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label CONTAINS[c] %@", text), evaluatedWith: place)
        waitForExpectations(timeout: 20)
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !element.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
    }
}
