//
//  RollCallUITests.swift
//  RollCallUITests
//
//  End-to-end tests that tap through the real app, like a person would,
//  against the real backend.
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

final class RollCallUITests: XCTestCase {

    /// A spot in Greenville, TX (the simulator's pretend location).
    private let greenville = CLLocation(latitude: 33.1385, longitude: -96.1108)

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Resident

    @MainActor
    func testRegisteringAHouseholdStepByStep() {
        let app = launchFresh()
        app.buttons["role_resident"].tap()
        app.buttons["registerHousehold"].tap()

        // 1. Home
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Test Resident\n")   // Return closes the keyboard, which brings back Next
        app.buttons["Use my current location"].tap()
        let address = app.textFields["addressField"]
        expect(address, valueContains: "", notEqualTo: "Fills in from the map, or type it", timeout: 20)
        snapshot(app, "wizard 1 home")
        app.buttons["wizardNext"].tap()

        // 2. People: one adult by default; add a senior, remove the adult -> lives alone
        let seniors = app.descendants(matching: .any)["counter_seniors"].firstMatch
        XCTAssertTrue(seniors.waitForExistence(timeout: 5))
        seniors.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()   // +
        app.descendants(matching: .any)["counter_adults"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.5)).tap()  // -
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'You live alone'")).firstMatch.waitForExistence(timeout: 5))
        snapshot(app, "wizard 2 people")
        app.buttons["wizardNext"].tap()

        // 3. Needs
        app.buttons["need_mobility"].tap()
        app.buttons["need_vehicle"].tap()
        app.buttons["equipment_oxygen"].tap()
        snapshot(app, "wizard 3 needs")
        app.buttons["wizardNext"].tap()

        // 4. Contact: Spanish, and ask for a buddy
        let spanish = app.buttons["language_es"]
        XCTAssertTrue(spanish.waitForExistence(timeout: 5))
        waitForStepAnimation()
        spanish.tap()
        XCTAssertTrue(spanish.isSelected, "Tapping Español didn't select it")
        let buddy = app.switches["wantsBuddyToggle"]
        scrollTo(buddy, in: app)
        buddy.switches.firstMatch.tap()
        snapshot(app, "wizard 4 contact")
        app.buttons["wizardNext"].tap()

        // 5. Review: Join is disabled until the resident agrees
        let join = app.buttons["wizardNext"]
        XCTAssertFalse(join.isEnabled)
        let consent = app.switches["consentToggle"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()   // the switch itself
        snapshot(app, "wizard 5 review")
        XCTAssertTrue(join.isEnabled)
        join.tap()

        XCTAssertTrue(app.staticTexts["Hi, Test"].waitForExistence(timeout: 15), "The new household's home didn't open")
        snapshot(app, "resident home after joining")

        // Delete my data really deletes it, and returns to the welcome screen.
        app.buttons["privacyLink"].tap()
        let delete = app.buttons["deleteMyData"]
        scrollTo(delete, in: app)
        snapshot(app, "privacy")
        delete.tap()
        app.buttons["Delete everything"].tap()
        XCTAssertTrue(app.buttons["role_resident"].waitForExistence(timeout: 15), "Didn't return to the welcome screen")
    }

    @MainActor
    func testActingAsADemoHousehold() {
        let app = launchFresh()
        app.buttons["role_resident"].tap()
        let greenvilleGroup = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Greenville'")).firstMatch
        XCTAssertTrue(greenvilleGroup.waitForExistence(timeout: 10))
        greenvilleGroup.tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'household_'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["You're on the roll call"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["editHousehold"].exists)
    }

    // MARK: - Buddy and responder

    @MainActor
    func testBuddySeesOnlyTheirNeighbors() {
        let app = launchFresh()
        app.buttons["role_buddy"].tap()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'volunteer_'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.staticTexts["Your neighbors"].waitForExistence(timeout: 10))
        snapshot(app, "buddy home")
    }

    @MainActor
    func testResponderSeesNoHouseholdsWithoutAnEmergency() {
        let app = launchFresh()
        app.buttons["role_responder"].tap()
        XCTAssertTrue(app.staticTexts["No active emergency"].waitForExistence(timeout: 10))
        // Switching roles goes back to the welcome screen.
        app.buttons["roleButton"].tap()
        app.buttons["Switch role"].tap()
        XCTAssertTrue(app.buttons["role_resident"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    /// Launch with no saved role, as if opening the app for the first time.
    @MainActor
    private func launchFresh() -> XCUIApplication {
        XCUIDevice.shared.location = XCUILocation(location: greenville)
        let app = XCUIApplication()
        app.launchArguments = ["-RCRole", "none"]
        app.launch()
        XCTAssertTrue(app.buttons["role_resident"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
    }

    @MainActor
    private func expect(_ element: XCUIElement, valueContains: String, notEqualTo placeholder: String, timeout: Double) {
        let predicate = NSPredicate(format: "value != %@ AND value != ''", placeholder)
        let found = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
        XCTAssertEqual(found, .completed, "The address never filled in from the location")
    }

    /// Each wizard step slides in; tapping mid-slide can miss the button.
    private func waitForStepAnimation() {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "step slides in")], timeout: 0.6)
    }

    /// Keep a picture of the screen in the test results.
    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
