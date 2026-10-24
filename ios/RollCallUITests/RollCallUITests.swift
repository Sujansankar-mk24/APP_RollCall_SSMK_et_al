//
//  RollCallUITests.swift
//  RollCallUITests
//
//  End-to-end tests that tap through the real app, exactly like a person
//  would, against the real backend: the Map and its incident log, sign-in,
//  Roll Call, Community, and the gear (profile, About, sign out).
//
//  Each test makes the accounts it needs (through the backend, like the app
//  does) and opens the app signed in as one of them. Before running them,
//  start the backend with fresh demo data, and make the test responder:
//      cd backend
//      source .venv/bin/activate
//      python -m scripts.clear_test_data    (keeps real accounts)
//      python -m scripts.make_responder test-responder@example.com "responder password"
//      uvicorn app.main:app
//  Run clear_test_data again afterwards to remove the tests' accounts.
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

    @MainActor
    func testLiveDataAndTheDemoTornadoWarning() throws {
        try setDemoWarning(on: true)
        defer { try? setDemoWarning(on: false) }   // other tests start without it
        let app = launchApp()

        // The Live sheet says where data comes from and that the demo is on.
        app.buttons["liveDataPill"].tap()
        XCTAssertTrue(app.switches["liveDataToggle"].waitForExistence(timeout: 15))
        app.swipeUp()   // full height, so the Demo section is on screen
        XCTAssertTrue(app.buttons["End the demo Tornado Warning"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()

        // The warning is on the map; tapping it explains it and its zones.
        let warning = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Demo. Tornado Warning'")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 15), "The demo warning isn't on the map")
        warning.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'DEMO. A tornado was spotted'")).firstMatch
            .waitForExistence(timeout: 10), "The Tornado Warning's sheet didn't open")
        snapshot(app, "demo tornado warning")
    }

    /// Switch the demo Tornado Warning on or off through the server, so the
    /// test always starts from a known state.
    private func setDemoWarning(on: Bool) throws {
        let helper = try newAccount("Test Helper")
        server("demo/tornado-warning", on ? "POST" : "DELETE", token: helper.token)
    }

    // MARK: - Incidents tab

    @MainActor
    func testIncidentLogOpensFromTheMapAndShowsAnIncident() {
        let app = launchApp()
        // The Incidents button (top left of the Map) unrolls the incident log.
        app.buttons["incidentsButton"].tap()

        // Four key numbers. "Active" matches what the server has right now
        // (other tests may have added reports since the demo data was reset).
        let active = app.descendants(matching: .any)["kpi_active"]
        XCTAssertTrue(active.waitForExistence(timeout: 15), "The KPI cards never appeared")
        let incidents = serverList("incidents")
        let open = incidents.filter { $0["status"] as? String == "active" }.count
        let responding = incidents.filter { $0["status"] as? String == "responding" }.count
        XCTAssertTrue(active.label.hasPrefix("Active incidents, \(open)"), "Unexpected: \(active.label)")
        XCTAssertTrue(active.label.contains("\(responding) responding"), "Unexpected: \(active.label)")
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

        snapshot(app, "incident log")

        // The X folds it up again, and the map is back.
        app.buttons["closeIncidents"].tap()
        XCTAssertTrue(app.buttons["reportIncidentButton"].isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["kpi_active"].isHittable)

        // Tapping a row folds the log up and shows that incident on the map.
        app.buttons["incidentsButton"].tap()
        let first = app.descendants(matching: .any)["incidentRow_1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(app.staticTexts["AI analysis"].waitForExistence(timeout: 10), "The incident's details didn't open")
    }

    // MARK: - Settings (the gear)

    @MainActor
    func testAboutOpensFromTheGearAndExplainsPrivacy() {
        let app = launchApp()
        XCTAssertFalse(app.buttons["tab_about"].exists, "About should live behind the gear, not in the tab bar")
        openSettings("About RollCall", in: app)
        XCTAssertTrue(app.staticTexts["What's in the app"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Who can see your information"].exists)
        app.buttons["closeAbout"].tap()
        XCTAssertTrue(app.buttons["reportIncidentButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProfileShowsWhoIsSignedInOnEveryTab() throws {
        let account = try newAccount("Paula Profile")
        let app = launchSignedIn(account)
        for tab in ["Map", "Roll Call", "Community"] {
            open(tab: tab, in: app)
            openSettings("Your profile", in: app)
            XCTAssertTrue(app.staticTexts["Paula Profile"].waitForExistence(timeout: 5), "No profile from the \(tab) tab")
            XCTAssertTrue(app.buttons["signOut"].exists)
            app.buttons["closeProfile"].tap()
            XCTAssertFalse(app.buttons["signOut"].waitForExistence(timeout: 2))
        }
    }

    // MARK: - Map location

    /// The first time, the iPhone asks for permission; after Allow, the map
    /// shows where you are.
    @MainActor
    func testUseMyLocationOnTheMapAsksPermissionThenShowsYou() {
        // Forget any earlier answer, so the permission popup really appears.
        XCUIApplication().resetAuthorizationStatus(for: .location)
        let app = launchApp()
        let button = app.buttons["useMyLocationOnMap"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "The location permission popup didn't appear")
        allow.tap()
        XCTAssertTrue(app.buttons["My location"].waitForExistence(timeout: 15), "The map didn't find the user")
    }

    // MARK: - Reporting

    @MainActor
    func testReportingAFireBesideAnExistingFireMergesIntoIt() {
        // Someone reported a fire here a moment ago (so it's recent enough to merge with).
        reportFire(at: besideGreenvilleFire)
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
    func testUseMyLocationPutsThePinWhereYouAre() {
        let app = launchApp()
        app.buttons["reportIncidentButton"].tap()
        let useMyLocation = app.buttons["useMyLocation"]
        XCTAssertTrue(useMyLocation.waitForExistence(timeout: 10))
        // Move the pin away first (search somewhere else), then come back.
        let search = app.textFields["addressSearchField"]
        app.swipeUp()
        search.tap()
        search.typeText("Sherman, TX")
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sherman, TX'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15))
        suggestion.tap()
        waitForPlaceName(in: app, containing: "Sherman")
        scrollTo(useMyLocation, in: app)
        useMyLocation.tap()
        waitForPlaceName(in: app, containing: "Greenville")
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

        signOut(app)
        XCTAssertTrue(app.textFields["emailField"].waitForExistence(timeout: 10), "Didn't return to sign-in")

        // A wrong password is refused with a clear message...
        signIn(app, email: email, password: "not my password")
        XCTAssertTrue(app.descendants(matching: .any)["signInError"].waitForExistence(timeout: 10))
        // ...and the right one opens the app.
        signIn(app, email: email, password: password)
        XCTAssertTrue(app.buttons["reportIncidentButton"].waitForExistence(timeout: 20))
    }

    @MainActor
    func testChoosingAServerChecksTheAddress() {
        let app = launch()
        let serverRow = app.buttons["serverRow"]
        scrollTo(serverRow, in: app)
        serverRow.tap()
        // An address with no RollCall server behind it is refused, with a reason.
        type("not-a-rollcall-server.invalid", into: app.textFields["serverAddressField"])
        app.buttons["connectServer"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH \"Couldn't reach a RollCall server\"")).firstMatch
            .waitForExistence(timeout: 15))
        // Going back to this Mac works, and the server is reachable again.
        app.buttons["useThisMac"].tap()
        XCTAssertTrue(app.buttons["serverRow"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["retryServer"].exists)
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

    @MainActor
    func testSignUpKeepsWhatYouTypeAndHelpsWithMistakes() {
        let app = launch()
        app.buttons["authMode_1"].tap()
        type("jordan tatum", into: app.textFields["signUpName"])
        let email = uniqueEmail()
        type(email, into: app.textFields["emailField"])
        // Typed text is never forced into capitals.
        XCTAssertEqual(app.textFields["signUpName"].value as? String, "jordan tatum")
        XCTAssertEqual(app.textFields["emailField"].value as? String, email)
        // The password rule is shown while typing, and the button waits for it.
        let password = app.secureTextFields["passwordField"]
        password.tap()
        dismissStrongPasswordSheet(app)
        password.tap()
        password.typeText("short")
        XCTAssertTrue(app.staticTexts["At least 8 characters (3 more)"].exists)
        XCTAssertFalse(app.buttons["submitAuth"].isEnabled)
    }

    @MainActor
    func testUsingAnEmailTwiceOffersToSignInInstead() {
        let app = launch()
        let email = uniqueEmail()
        signUp(app, name: "First Person", email: email)
        XCTAssertTrue(app.buttons["reportIncidentButton"].waitForExistence(timeout: 20))
        signOut(app)

        signUp(app, name: "Second Person", email: email)
        XCTAssertTrue(app.descendants(matching: .any)["signInError"].waitForExistence(timeout: 10))
        // One tap signs in with what was already typed.
        app.buttons["signInInstead"].tap()
        XCTAssertTrue(app.buttons["reportIncidentButton"].waitForExistence(timeout: 20))
    }

    // MARK: - Roll Call tab: resident

    @MainActor
    func testNotNowSkipsTheRollCall() {
        let app = launch(tab: "rollCall")
        signUp(app, name: "Test Person", email: uniqueEmail())
        let notNow = app.buttons["notNow"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 15))
        scrollTo(notNow, in: app)
        tap(notNow, until: app.descendants(matching: .any)["optedOut"], in: app)
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
        tap(app.buttons["wizardNext"], until: app.buttons["need_mobility"], in: app)

        // 3. Needs
        app.buttons["need_mobility"].tap()
        app.buttons["need_vehicle"].tap()
        app.buttons["equipment_oxygen"].tap()
        snapshot(app, "wizard 3 needs")
        // The page may still be scrolling from the taps above, which can swallow a tap.
        tap(app.buttons["wizardNext"], until: app.buttons["language_es"], in: app)

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

        XCTAssertTrue(app.staticTexts["Test Resident"].waitForExistence(timeout: 15), "The new household's home didn't open")
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
    func testResidentAcceptsAVolunteersOffer() throws {
        // A resident on the roll call, and a volunteer who typed their address.
        let resident = try newAccount("Rosa Tester")
        let address = try registerHousehold(for: resident)
        let volunteer = try newAccount("Victor Volunteer")
        server("me/volunteer", "PUT", ["city": "Greenville"], token: volunteer.token)
        server("buddy/requests/address", "POST", address, token: volunteer.token)

        let app = launchSignedIn(resident, tab: "rollCall")
        let accept = app.buttons["acceptBuddy"]
        XCTAssertTrue(accept.waitForExistence(timeout: 15), "The resident should see the volunteer's offer")
        snapshot(app, "buddy request")
        accept.tap()
        XCTAssertTrue(text("Your buddy", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["acceptBuddy"].exists)
    }

    // MARK: - Roll Call tab: volunteer and responder

    @MainActor
    func testVolunteerAsksToCheckOnSomeoneByAddress() throws {
        let volunteer = try newAccount("Victor Volunteer")
        server("me/volunteer", "PUT", ["city": "Greenville"], token: volunteer.token)
        let app = launchSignedIn(volunteer, tab: "rollCall")
        let section = app.buttons["section_buddy"]
        XCTAssertTrue(section.waitForExistence(timeout: 15))
        section.tap()
        XCTAssertTrue(text("Neighbors you check on", in: app).waitForExistence(timeout: 10))
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
    func testResponderSeesNoHouseholdsWithoutAnEmergency() throws {
        let app = launchSignedIn(try responderAccount(), tab: "rollCall")
        XCTAssertTrue(app.staticTexts["No active emergency"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["tab_community"].exists, "Responders don't join communities")
    }

    // MARK: - Community tab

    @MainActor
    func testAskingToJoinACommunity() throws {
        let admin = try newAccount("Ada Admin")
        let name = "Join Test \(Int.random(in: 100_000...999_999))"
        server("communities", "POST", ["name": name, "city": "Greenville"], token: admin.token)

        let app = launch(tab: "community")
        signUp(app, name: "New Neighbor", email: uniqueEmail())
        let search = app.textFields["communitySearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        type(name, into: search)
        let join = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'join_'")).firstMatch
        XCTAssertTrue(join.waitForExistence(timeout: 10), "\(name) wasn't found")
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
        tap(create, until: app.textFields["communityNameField"], in: app)
        type("Test Hollow \(Int(Date().timeIntervalSince1970))", into: app.textFields["communityNameField"])
        type("Greenville", into: app.textFields["communityCityField"])
        app.buttons["confirmCreateCommunity"].tap()
        let header = app.descendants(matching: .any)["communityHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.label.contains("You're the admin"), "Unexpected: \(header.label)")
    }

    @MainActor
    func testAdminApprovesAJoinRequest() throws {
        let admin = try newAccount("Ada Admin")
        try communityWithJoinRequest(admin: admin)
        let app = launchSignedIn(admin, tab: "community")
        let approve = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'approve_'")).firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 15), "The admin should see the join request")
        snapshot(app, "community admin")
        approve.tap()
        XCTAssertTrue(approve.waitForNonExistence(timeout: 10))
    }

    // MARK: - Screenshot tour

    /// Opens every main screen in light and dark mode and keeps a picture of
    /// each (in the test results), so the whole app can be checked by eye.
    @MainActor
    func testScreenshotTourOfEveryScreen() throws {
        // A resident who runs a community (with someone asking to join) and
        // has a buddy offer waiting; a volunteer; and a responder if one exists.
        let resident = try newAccount("Rosa Tester")
        let address = try registerHousehold(for: resident)
        let volunteer = try newAccount("Victor Volunteer")
        server("me/volunteer", "PUT", ["city": "Greenville"], token: volunteer.token)
        // The offer comes first: once Rosa runs a community, outside volunteers
        // can't offer unless she allows it (the community rule).
        server("buddy/requests/address", "POST", address, token: volunteer.token)
        try communityWithJoinRequest(admin: resident)
        let responder = try? responderAccount()

        for mode in ["light", "dark"] {
            var app = launch(arguments: ["-appearanceMode", mode])
            snapshot(app, "\(mode) 01 sign in")
            app.terminate()

            // The Map and everything on it.
            app = launchSignedIn(resident, arguments: ["-appearanceMode", mode])
            XCTAssertTrue(app.buttons["reportIncidentButton"].waitForExistence(timeout: 20))
            snapshot(app, "\(mode) 02 map")
            app.buttons["incidentsButton"].tap()
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'incidentRow_'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            snapshot(app, "\(mode) 03 incident log")
            row.tap()
            XCTAssertTrue(app.staticTexts["AI analysis"].waitForExistence(timeout: 10))
            snapshot(app, "\(mode) 04 incident detail")
            app.swipeDown(velocity: .fast)
            app.buttons["liveDataPill"].tap()
            XCTAssertTrue(app.switches["liveDataToggle"].waitForExistence(timeout: 10))
            snapshot(app, "\(mode) 05 live data")
            app.buttons["Done"].tap()
            app.buttons["reportIncidentButton"].tap()
            XCTAssertTrue(app.buttons["sendReportButton"].waitForExistence(timeout: 10))
            snapshot(app, "\(mode) 06 report form")
            app.buttons["Cancel"].firstMatch.tap()

            // Roll Call, Community, and the gear's pages.
            open(tab: "Roll Call", in: app)
            XCTAssertTrue(app.buttons["acceptBuddy"].waitForExistence(timeout: 10))
            snapshot(app, "\(mode) 07 roll call")
            open(tab: "Community", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["communityHeader"].waitForExistence(timeout: 10))
            snapshot(app, "\(mode) 08 community")
            openSettings("Your profile", in: app)
            XCTAssertTrue(app.buttons["signOut"].waitForExistence(timeout: 5))
            snapshot(app, "\(mode) 09 profile")
            app.buttons["closeProfile"].tap()
            openSettings("About RollCall", in: app)
            XCTAssertTrue(app.buttons["closeAbout"].waitForExistence(timeout: 5))
            snapshot(app, "\(mode) 09 about")
            app.terminate()

            // A volunteer's "I check on", and the responder view.
            app = launchSignedIn(volunteer, tab: "rollCall", arguments: ["-appearanceMode", mode])
            XCTAssertTrue(app.buttons["section_buddy"].waitForExistence(timeout: 15))
            app.buttons["section_buddy"].tap()
            XCTAssertTrue(text("Neighbors you check on", in: app).waitForExistence(timeout: 10))
            snapshot(app, "\(mode) 10 i check on")
            app.terminate()
            if let responder {
                app = launchSignedIn(responder, tab: "rollCall", arguments: ["-appearanceMode", mode])
                XCTAssertTrue(app.staticTexts["No active emergency"].waitForExistence(timeout: 15))
                snapshot(app, "\(mode) 11 responder")
                app.terminate()
            }
        }
    }

    // MARK: - Helpers

    /// Tap the gear on the current tab, then one of its menu items.
    @MainActor
    private func openSettings(_ item: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["settingsButton"].firstMatch.waitForExistence(timeout: 10), "No gear button")
        let entry = app.buttons[item]
        // Up to three tries: iOS's late "Save Password?" popup can swallow a tap.
        for attempt in 0..<3 {
            if attempt > 0 { dismissSavePasswordPrompt(app) }
            let gear = app.buttons.matching(identifier: "settingsButton").allElementsBoundByIndex.first { $0.isHittable }
                ?? app.buttons["settingsButton"].firstMatch
            gear.tap()
            if entry.waitForExistence(timeout: 4) { entry.tap(); return }
        }
        XCTFail("No \(item) in the gear's menu")
    }

    /// Gear > Your profile > Sign out.
    @MainActor
    private func signOut(_ app: XCUIApplication) {
        openSettings("Your profile", in: app)
        let button = app.buttons["signOut"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private let password = "correct horse battery"

    /// Start the app signed out, optionally opening on a tab after signing in.
    @MainActor
    private func launch(tab: String? = nil, arguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.location = XCUILocation(location: greenville)
        let app = XCUIApplication()
        app.launchArguments = ["-RCSignOut", "YES", "-RCServerURL", "http://localhost:8000"]
            + (tab.map { ["-RSTab", $0] } ?? []) + arguments
        app.launch()
        if !app.textFields["emailField"].waitForExistence(timeout: 20) {
            XCTFail("The sign-in screen didn't appear. Is the backend running? (uvicorn app.main:app)")
        }
        return app
    }

    /// Start the app already signed in as an account a test just made.
    @MainActor
    private func launchSignedIn(_ account: Account, tab: String? = nil, arguments: [String] = [],
                                at location: CLLocation? = nil) -> XCUIApplication {
        XCUIDevice.shared.location = XCUILocation(location: location ?? greenville)
        let app = XCUIApplication()
        app.launchArguments = ["-RCSignOut", "YES", "-RCToken", account.token, "-RCServerURL", "http://localhost:8000"]
            + (tab.map { ["-RSTab", $0] } ?? []) + arguments
        app.launch()
        if !app.descendants(matching: .any)["mainTabBar"].waitForExistence(timeout: 20) {
            XCTFail("The app didn't open signed in. Is the backend running? (uvicorn app.main:app)")
        }
        return app
    }

    /// For the Map tests: a new account, on the map, next to the demo grass fire.
    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let account: Account
        do { account = try newAccount("Map Tester") } catch {
            XCTFail("Couldn't make a test account: \(error)")
            return XCUIApplication()
        }
        let app = launchSignedIn(account, arguments: arguments, at: besideGreenvilleFire)
        if !app.buttons["reportIncidentButton"].waitForExistence(timeout: 20) {
            XCTFail("The map didn't load.")
        }
        return app
    }

    // MARK: - Setting things up through the server (like the app does)

    struct Account {
        let email: String
        let token: String
    }

    /// Send a request to the backend and return its JSON answer.
    @discardableResult
    private func server(_ path: String, _ method: String = "GET", _ body: [String: Any]? = nil,
                        token: String? = nil) -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://localhost:8000")!.appending(path: path))
        request.httpMethod = method
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let done = XCTestExpectation(description: path)
        var answer: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in answer = data; done.fulfill() }.resume()
        _ = XCTWaiter.wait(for: [done], timeout: 30)
        return answer.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    /// A backend list, like GET /incidents.
    private func serverList(_ path: String) -> [[String: Any]] {
        let done = XCTestExpectation(description: path)
        var answer: Data?
        URLSession.shared.dataTask(with: URL(string: "http://localhost:8000")!.appending(path: path)) { data, _, _ in
            answer = data; done.fulfill()
        }.resume()
        _ = XCTWaiter.wait(for: [done], timeout: 30)
        return answer.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
    }

    /// Send a fire report through the backend, like the app's report form does.
    private func reportFire(at location: CLLocation) {
        var request = URLRequest(url: URL(string: "http://localhost:8000/reports")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("type=fire&latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&location_name=FM%201570".utf8)
        let done = XCTestExpectation(description: "report")
        URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
        _ = XCTWaiter.wait(for: [done], timeout: 30)
    }

    private func newAccount(_ name: String) throws -> Account {
        let email = uniqueEmail()
        let answer = server("auth/signup", "POST", ["name": name, "email": email, "password": password])
        let token = try XCTUnwrap(answer["token"] as? String, "Couldn't sign up through the backend. Is it running?")
        return Account(email: email, token: token)
    }

    /// Join the roll call with a made-up address near Greenville. Returns the
    /// address (as the buddy-request body), so a volunteer can type it.
    private func registerHousehold(for account: Account) throws -> [String: Any] {
        let street = "\(Int.random(in: 1_000...9_999)) Test Lane"
        let household = server("households", "POST", [
            "contact_name": "Rosa Tester", "address": street, "city": "Greenville", "zip_code": "75401",
            "latitude": 33.14, "longitude": -96.11, "seniors": 1, "wants_buddy": true,
        ], token: account.token)
        XCTAssertNotNil(household["id"], "Couldn't register the test household")
        return ["address": street, "city": "Greenville", "zip_code": "75401"]
    }

    /// A community run by `admin`, with one other person asking to join.
    private func communityWithJoinRequest(admin: Account) throws {
        let community = server("communities", "POST",
                               ["name": "Test Hollow \(Int.random(in: 100_000...999_999))", "city": "Greenville"],
                               token: admin.token)
        let id = try XCTUnwrap(community["id"] as? Int, "Couldn't create the test community")
        let newcomer = try newAccount("Grace Newcomer")
        server("communities/\(id)/join", "POST", token: newcomer.token)
    }

    /// The responder account for tests. Responders are issued, not signed up, so
    /// make it once before testing:
    ///   python -m scripts.make_responder test-responder@example.com "responder password"
    private func responderAccount() throws -> Account {
        let email = "test-responder@example.com"
        let answer = server("auth/signin", "POST", ["email": email, "password": "responder password"])
        guard let token = answer["token"] as? String else {
            throw XCTSkip("No test responder. Run: python -m scripts.make_responder \(email) \"responder password\"")
        }
        return Account(email: email, token: token)
    }

    /// Tap a tab. If a late system prompt swallowed the tap, close it and try again.
    @MainActor
    private func open(tab: String, in app: XCUIApplication) {
        let name = tab.replacingOccurrences(of: " ", with: "")
        let button = app.buttons["tab_\(name.prefix(1).lowercased() + name.dropFirst())"]
        for _ in 0..<3 {
            button.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: button)
            if XCTWaiter.wait(for: [selected], timeout: 4) == .completed { return }
            dismissSavePasswordPrompt(app)
        }
        XCTFail("Couldn't open the \(tab) tab")
    }

    /// Text on screen, ignoring upper/lower case (sheet labels are shown in capitals).
    @MainActor
    private func text(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
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
    private func signUp(_ app: XCUIApplication, name: String, email: String) {
        app.buttons["authMode_1"].tap()   // the "Create account" tab
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
        _ = app.descendants(matching: .any)["mainTabBar"].waitForExistence(timeout: 20)
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

    /// Tap a field and type. If a late system prompt took the tap (no keyboard
    /// appeared), close it and tap again.
    @MainActor
    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let app = XCUIApplication()
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) { break }
            dismissSavePasswordPrompt(app)
        }
        field.typeText(text)
    }

    private func uniqueEmail() -> String {
        "test-\(UUID().uuidString.prefix(8).lowercased())@example.com"
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
