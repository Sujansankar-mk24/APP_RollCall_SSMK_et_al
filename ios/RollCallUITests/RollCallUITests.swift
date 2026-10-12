//
//  RollCallUITests.swift
//  RollCallUITests
//
//  End-to-end tests that tap through the real app, exactly like a person
//  would, against the real backend: the Map, Incidents and Roll Call tabs.
//
//  Most tests open a fictional demo account from the sign-in screen; a few
//  create a brand-new account. Before running them, start the backend with
//  fresh demo data:
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

    // MARK: - Accounts

    @MainActor
    func testCreatingAnAccountThenSigningOutAndBackIn() {
        let app = launch()
        let email = uniqueEmail()
        signUp(app, name: "Test Person", email: email)
        XCTAssertTrue(app.buttons["reportIncidentButton"].waitForExistence(timeout: 20), "Didn't open the app after signing up")

        open(tab: "About", in: app)
        let signOut = app.buttons["signOut"]
        scrollTo(signOut, in: app)
        signOut.tap()
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 10), "Didn't return to sign-in")

        // A wrong password is refused with a clear message...
        signIn(app, email: email, password: "not my password")
        XCTAssertTrue(app.descendants(matching: .any)["signInError"].waitForExistence(timeout: 10))
        // ...and the right one opens the app.
        signIn(app, email: email, password: password)
        XCTAssertTrue(app.buttons["reportIncidentButton"].waitForExistence(timeout: 20))
    }

    @MainActor
    func testTheAppRemembersWhoIsSignedIn() {
        let app = launch()
        signUp(app, name: "Test Person", email: uniqueEmail())
        XCTAssertTrue(app.buttons["reportIncidentButton"].waitForExistence(timeout: 20))
        // Open the app again, WITHOUT signing out: it goes straight in.
        app.terminate()
        let again = XCUIApplication()
        again.launch()
        XCTAssertTrue(again.buttons["reportIncidentButton"].waitForExistence(timeout: 20))
        XCTAssertFalse(again.textFields["emailField"].exists)
    }

    // MARK: - Roll Call tab: resident

    @MainActor
    func testNotNowSkipsTheRollCall() {
        let app = launch(tab: "rollCall")
        signUp(app, name: "Test Person", email: uniqueEmail())
        let notNow = app.buttons["notNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 15))
        scrollTo(notNow, in: app)
        notNow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["optedOut"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["joinRollCall"].exists, "Should still be able to join later")
    }

    @MainActor
    func testRegisteringAHouseholdStepByStep() {
        let app = launch(tab: "rollCall")
        signUp(app, name: "Test Resident", email: uniqueEmail())
        let join = app.buttons["joinRollCall"]
        XCTAssertTrue(join.waitForExistence(timeout: 15))
        snapshot(app, "roll call join card")
        scrollTo(join, in: app)
        let name = app.textFields["nameField"]
        tap(join, until: name, in: app)

        // 1. Home: the name comes from the account; the location button fills in
        //    the address (street, town and ZIP), which can still be edited.
        XCTAssertEqual(name.value as? String, "Test Resident")
        app.buttons["Use my current location"].tap()
        let zip = app.textFields["zipField"]
        let fiveDigits = NSPredicate(format: "value MATCHES '[0-9]{5}'")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: fiveDigits, object: zip)], timeout: 20),
                       .completed, "The ZIP code never filled in from the location")
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
        let finish = app.buttons["wizardNext"]
        XCTAssertFalse(finish.isEnabled)
        let consent = app.switches["consentToggle"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()   // the switch itself
        snapshot(app, "wizard 5 review")
        XCTAssertTrue(finish.isEnabled)
        finish.tap()

        XCTAssertTrue(app.staticTexts["Hi, Test"].waitForExistence(timeout: 15), "The new household's home didn't open")
        snapshot(app, "resident home after joining")

        // Delete my data really deletes it, and offers to join again.
        let privacy = app.buttons["privacyLink"]
        scrollTo(privacy, in: app)
        privacy.tap()
        let delete = app.buttons["deleteMyData"]
        scrollTo(delete, in: app)
        snapshot(app, "privacy")
        delete.tap()
        app.buttons["Delete everything"].tap()
        XCTAssertTrue(app.buttons["joinRollCall"].waitForExistence(timeout: 15), "Didn't return to the join card")
    }

    @MainActor
    func testResidentAcceptsAVolunteersOffer() {
        let app = launch(tab: "rollCall")
        openDemoAccount(app, kind: "resident")
        let accept = app.buttons["acceptBuddy"]
        XCTAssertTrue(accept.waitForExistence(timeout: 15), "The demo resident should have a buddy request (reset the demo data)")
        snapshot(app, "buddy request")
        accept.tap()
        XCTAssertTrue(app.staticTexts["Your buddy"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["acceptBuddy"].exists)
    }

    // MARK: - Roll Call tab: volunteer and responder

    @MainActor
    func testVolunteerAsksToCheckOnSomeoneByAddress() {
        let app = launch(tab: "rollCall")
        openDemoAccount(app, kind: "volunteer")
        let section = app.segmentedControls["rollCallSection"]
        XCTAssertTrue(section.waitForExistence(timeout: 15))
        section.buttons["I check on"].tap()
        XCTAssertTrue(app.staticTexts["Neighbors you check on"].waitForExistence(timeout: 10))
        snapshot(app, "volunteer")

        let ask = app.buttons["askByAddress"]
        scrollTo(ask, in: app)
        ask.tap()
        type("999 Nowhere Rd", into: app.textFields["buddyAddressField"])
        type("Greenville", into: app.textFields["buddyCityField"])
        type("75401", into: app.textFields["buddyZipField"])
        app.buttons["sendBuddyRequest"].tap()
        // The same answer whether or not anyone lives there.
        XCTAssertTrue(app.descendants(matching: .any)["buddyRequestSent"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testResponderSeesNoHouseholdsWithoutAnEmergency() {
        let app = launch(tab: "rollCall")
        openDemoAccount(app, kind: "responder")
        XCTAssertTrue(app.staticTexts["No active emergency"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.buttons["Community"].exists, "Responders don't join communities")
    }

    // MARK: - Community tab

    @MainActor
    func testAskingToJoinACommunity() {
        let app = launch(tab: "community")
        signUp(app, name: "New Neighbor", email: uniqueEmail())
        let search = app.textFields["communitySearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        type("Pecan", into: search)
        let join = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'join_'")).firstMatch
        XCTAssertTrue(join.waitForExistence(timeout: 10), "Pecan Hollow wasn't found")
        join.tap()
        XCTAssertTrue(app.staticTexts["pendingCommunity"].waitForExistence(timeout: 10), "Should be waiting for the admin")
    }

    @MainActor
    func testStartingACommunityMakesYouItsAdmin() {
        let app = launch(tab: "community")
        signUp(app, name: "Founder", email: uniqueEmail())
        let create = app.buttons["createCommunity"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        scrollTo(create, in: app)
        create.tap()
        type("Test Hollow \(Int(Date().timeIntervalSince1970))", into: app.textFields["communityNameField"])
        type("Greenville", into: app.textFields["communityCityField"])
        app.buttons["confirmCreateCommunity"].tap()
        let header = app.descendants(matching: .any)["communityHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.label.contains("You're the admin"), "Unexpected: \(header.label)")
    }

    @MainActor
    func testAdminApprovesAJoinRequest() {
        let app = launch(tab: "community")
        openDemoAccount(app, kind: "resident")   // the demo resident runs Pecan Hollow
        let approve = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'approve_'")).firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 15), "The demo community should have a join request (reset the demo data)")
        snapshot(app, "community admin")
        approve.tap()
        XCTAssertTrue(approve.waitForNonExistence(timeout: 10))
    }

    // MARK: - Helpers

    private let password = "correct horse battery"

    /// Start the app signed out, optionally opening on a tab after signing in.
    @MainActor
    private func launch(tab: String? = nil) -> XCUIApplication {
        XCUIDevice.shared.location = XCUILocation(location: greenville)
        let app = XCUIApplication()
        app.launchArguments = ["-RCSignOut", "YES"] + (tab.map { ["-RSTab", $0] } ?? [])
        app.launch()
        if !app.textFields["emailField"].waitForExistence(timeout: 20) {
            XCTFail("The sign-in screen didn't appear. Is the backend running? (uvicorn app.main:app)")
        }
        return app
    }

    /// For the Map/Incidents tests: signed in as the demo resident, on the map.
    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.location = XCUILocation(location: besideGreenvilleFire)
        let app = XCUIApplication()
        app.launchArguments = ["-RCSignOut", "YES"] + arguments
        app.launch()
        openDemoAccount(app, kind: "resident")
        if !app.buttons["reportIncidentButton"].waitForExistence(timeout: 20) {
            XCTFail("The map didn't load. Is the backend running? (uvicorn app.main:app)")
        }
        return app
    }

    /// Tap a tab. If a late system prompt swallowed the tap, close it and try again.
    @MainActor
    private func open(tab: String, in app: XCUIApplication) {
        tap(app.tabBars.buttons[tab], until: app.navigationBars[tab], in: app)
    }

    /// Tap `button` until `result` appears, closing a late "Save Password?"
    /// prompt in between if it swallowed the tap.
    @MainActor
    private func tap(_ button: XCUIElement, until result: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 {
            button.tap()
            if result.waitForExistence(timeout: 4) { return }
            dismissSavePasswordPrompt(app)
        }
        XCTFail("Tapping \(button) didn't work")
    }

    @MainActor
    private func openDemoAccount(_ app: XCUIApplication, kind: String) {
        let button = app.buttons["demo_\(kind)"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "No demo \(kind) account. Run python -m scripts.reset_demo")
        scrollTo(button, in: app)
        button.tap()
    }

    @MainActor
    private func signUp(_ app: XCUIApplication, name: String, email: String) {
        app.segmentedControls["authMode"].buttons["Create account"].tap()
        type(name, into: app.textFields["signUpName"])
        type(email, into: app.textFields["emailField"])
        let secret = app.secureTextFields["passwordField"]
        XCTAssertTrue(secret.waitForExistence(timeout: 10))
        secret.tap()
        dismissStrongPasswordSheet(app)
        secret.tap()
        secret.typeText(password)
        app.buttons["submitAuth"].tap()
        dismissSavePasswordPrompt(app)
    }

    /// After a new account, iOS may ask "Save Password?" a moment after the app
    /// opens. The test waits for the app, then answers Not Now if it's asked.
    @MainActor
    private func dismissSavePasswordPrompt(_ app: XCUIApplication) {
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 20)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            for place in [app, springboard] where place.buttons["Not Now"].exists {
                place.buttons["Not Now"].tap()
                return
            }
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "poll")], timeout: 0.5)
        }
    }

    /// When creating an account, iOS offers "Use Strong Password?". A person
    /// could accept it; the test closes it and types its own password.
    @MainActor
    private func dismissStrongPasswordSheet(_ app: XCUIApplication) {
        let offer = app.buttons["Fill Strong Password"]
        guard offer.waitForExistence(timeout: 3) else { return }
        let close = app.buttons["xmark"]   // the sheet's X button
        let hittable = NSPredicate(format: "hittable == true")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: close)], timeout: 5)
        close.tap()
        XCTAssertTrue(offer.waitForNonExistence(timeout: 5), "Couldn't close the Strong Password sheet")
    }

    @MainActor
    private func signIn(_ app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["emailField"]
        if (emailField.value as? String) != email {   // after a failed try, the email is still there
            type(email, into: emailField)
        }
        // A password field empties itself when tapped again, like on any iPhone.
        type(password, into: app.secureTextFields["passwordField"])
        app.buttons["submitAuth"].tap()
    }

    @MainActor
    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text)
    }

    private func uniqueEmail() -> String {
        "test\(Int(Date().timeIntervalSince1970 * 1000))@example.com"
    }

    @MainActor
    private func waitForPlaceName(in app: XCUIApplication, containing text: String) {
        let place = app.staticTexts["pinPlaceName"]
        XCTAssertTrue(place.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label CONTAINS[c] %@", text), evaluatedWith: place)
        waitForExpectations(timeout: 20)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
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
