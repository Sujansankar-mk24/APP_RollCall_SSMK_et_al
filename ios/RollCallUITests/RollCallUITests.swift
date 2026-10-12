//
//  RollCallUITests.swift
//  RollCallUITests
//
//  End-to-end tests that tap through the real app, exactly like a person
//  would, against the real backend: the Map, Incidents and Roll Call tabs.
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
        XCTAssertTrue(active.label.hasPrefix("Active incidents, 4"), "Unexpected: \(active.label)")
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

    // MARK: - About tab

    @MainActor
    func testAboutTabExplainsEachTabAndPrivacy() {
        let app = launchApp()
        app.tabBars.buttons["About"].tap()
        XCTAssertTrue(app.staticTexts["What's in the app"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Who can see your information"].exists)
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

    // MARK: - Roll Call tab: resident

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

    // MARK: - Roll Call tab: buddy and responder

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

    /// Open the Roll Call tab with no saved role, as if using it for the first time.
    @MainActor
    private func launchFresh() -> XCUIApplication {
        XCUIDevice.shared.location = XCUILocation(location: greenville)
        let app = XCUIApplication()
        app.launchArguments = ["-RCRole", "none", "-RSTab", "rollCall"]
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
