//
//  DemoWalkthrough.swift
//  RescueSightUITests
//
//  NOT a real test. This drives the whole app so a screen recording can be
//  made (see tools/record_demo.sh). It is skipped in normal test runs and only
//  runs when RS_DEMO=1 is set.
//
//  For every step it writes a line to an events file:
//    * a caption (what is being shown and what is being done), and
//    * where it taps or drags (so the video can draw a ring there).
//  tools/make_demo_video.py turns those events into captions, tap rings and a
//  voice-over on top of the recording.
//
//  Environment variables:
//    RS_DEMO=1            required, or every test here is skipped
//    RS_EVENTS_FILE       where to write events (default /private/tmp/rs_demo_events.jsonl)
//    RS_SCENES=3,5        run only some scenes (for debugging)
//    RS_FAST=1            skip the pauses (for debugging)
//    RS_PHOTO_LABEL       pick the library photo whose label starts with this
//

import CoreLocation
import XCTest

@MainActor
final class DemoWalkthrough: XCTestCase {

    private var app = XCUIApplication()
    private var sceneNumber = 0
    private var sceneTitle = ""
    private let besideGreenvilleFire = CLLocation(latitude: 33.0712, longitude: -96.1043)

    private let environment = ProcessInfo.processInfo.environment
    private var isFast: Bool { environment["RS_FAST"] == "1" }
    private var eventsPath: String { environment["RS_EVENTS_FILE"] ?? "/private/tmp/rs_demo_events.jsonl" }

    /// Attach a picture of the screen to the test result (used to debug a run).
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - The two recordings

    /// Recording 1: the whole app, backend running.
    func testWalkthrough() throws {
        try XCTSkipUnless(environment["RS_DEMO"] == "1", "Only runs for the demo recording (RS_DEMO=1)")
        continueAfterFailure = false
        let only = Set((environment["RS_SCENES"] ?? "").split(separator: ",").compactMap { Int($0) })
        func wanted(_ n: Int) -> Bool { only.isEmpty || only.contains(n) }

        launchApp()
        emit(["k": "start"])

        if wanted(1) { sceneMap(); snapshot("after scene 1") }
        if wanted(2) { sceneNightMode(); snapshot("after scene 2") }
        if wanted(3) || wanted(4) || wanted(5) {
            sceneIncidentSheet(details: wanted(3), drone: wanted(4), priority: wanted(5)); snapshot("after scenes 3-5")
        }
        if wanted(6) { sceneSevereWeather(); snapshot("after scene 6") }
        if wanted(7) { sceneReport(); snapshot("after scene 7") }
        if wanted(8) { sceneIncidentsTab(); snapshot("after scene 8") }

        emit(["k": "end"])
    }

    /// Recording 2: the backend is OFF when the app opens. The recording script
    /// starts it again when this test drops a signal file.
    func testOfflineState() throws {
        try XCTSkipUnless(environment["RS_DEMO"] == "1", "Only runs for the demo recording (RS_DEMO=1)")
        continueAfterFailure = false
        app = XCUIApplication()
        XCUIDevice.shared.location = XCUILocation(location: besideGreenvilleFire)
        app.launch()
        emit(["k": "start"])
        beginScene(9, "Offline")

        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 30), "The offline screen never appeared")
        say("When the backend is off",
            "The incident server is switched off right now. Instead of crashing or showing a blank screen, the app explains what happened in plain words and offers a Try again button.",
            doing: "Opening RescueSight with the backend stopped.")
        step("Trying again while it's still off",
             "Tapping Try again with the server still off just shows the same error. Nothing is lost.",
             doing: "Tapping Try again.") {
            self.tap(retry)
        }
        step("Starting the backend again",
             "Starting the Python server again in the background. The app has no idea yet.",
             doing: "Switching the backend back on.") {
            FileManager.default.createFile(atPath: "/private/tmp/rs_signal_start_backend", contents: Data())
        }
        // Keep tapping Try again until the map loads.
        let deadline = Date().addingTimeInterval(60)
        var attempts = 0
        while !app.buttons["reportIncidentButton"].exists && Date() < deadline {
            if attempts == 0 {
                say("Tapping Try again", "Now the server answers, so Try again works and the map comes back.",
                    doing: "Tapping Try again.", hold: false)
            }
            attempts += 1
            if retry.exists, retry.isHittable { tap(retry) }
            hold(3)
        }
        XCTAssertTrue(app.buttons["reportIncidentButton"].waitForExistence(timeout: 15))
        say("Back online", "The map and every incident are back, with nothing lost. If the server drops while the app is open, it keeps the last data on screen with an Offline warning instead.",
            doing: "The map reloaded.")
        snapshot("after scene 9")
        emit(["k": "end"])
    }

    // MARK: - Scenes

    private func sceneMap() {
        beginScene(1, "Map")
        say("The map",
            "Every incident reported in North Texas is a colored zone with an icon for its type. Red means active, amber means responders are on the way, and gray means resolved.",
            doing: "Opening RescueSight on an iPhone simulator.")
        say("Live status and legend",
            "The pill at top left says when the data was last updated, and it refreshes by itself. The legend explains the colors. A bigger zone means more people reported the same incident.",
            doing: "Pointing out the update time and the legend.")

        step("Zooming in", "Pinching works on a real phone. In the simulator, these buttons zoom the map.",
             doing: "Tapping the plus button three times.") {
            for _ in 0..<3 { self.tap(self.app.buttons["zoomInButton"]); self.hold(0.9) }
        }
        step("Zooming out", "The minus button zooms back out.", doing: "Tapping the minus button three times.") {
            for _ in 0..<3 { self.tap(self.app.buttons["zoomOutButton"]); self.hold(0.9) }
        }
        step("Recenter", "The target button returns to the whole North Texas view.", doing: "Tapping the recenter button.") {
            self.tap(self.app.buttons["Recenter map"])
        }

        step("Filter by mode: severe weather",
             "Incidents come in ten types, grouped into modes. Choosing Severe weather only hides everything except tornadoes, storms, rain, floods, hurricanes and winter storms.",
             doing: "Opening the Type chip and choosing Severe weather only.") {
            self.tap(self.app.buttons["Incident type filter"]); self.hold(1.2)
            self.tap(self.app.buttons["Severe weather only"])
        }
        step("Back to all incidents", "A Clear chip appears whenever a filter is on. The Type menu also has an All incidents mode.",
             doing: "Opening the Type chip and choosing All incidents.") {
            self.tap(self.app.buttons["Incident type filter"]); self.hold(1.2)
            self.tap(self.app.buttons["All incidents"])
        }

        step("Filter by status",
             "Switching off Resolved hides the gray zones, so a responder sees only what still needs attention.",
             doing: "Opening the Status chip and switching off Resolved.") {
            self.tap(self.app.buttons["Status filter"]); self.hold(1.2)
            let resolved = self.app.buttons["Resolved"]
            if resolved.waitForExistence(timeout: 3) { self.tap(resolved) }
        }
        step("Show all statuses again", "One tap restores every status.", doing: "Choosing Show all statuses.") {
            let all = self.app.buttons["Show all statuses"]
            if all.waitForExistence(timeout: 3) { self.tap(all) }
        }

        step("Filter by time",
             "The time chip shows the last 24 hours or the last 7 days. The two older incidents disappear when I pick 24 hours.",
             doing: "Opening the time chip and choosing Last 24 hours.") {
            self.tap(self.app.buttons["Time filter"]); self.hold(1.2)
            self.tap(self.app.buttons["Last 24 hours"])
        }
        step("Back to 7 days", "Restoring the default.", doing: "Choosing Last 7 days.") {
            self.tap(self.app.buttons["Time filter"]); self.hold(1.2)
            self.tap(self.app.buttons["Last 7 days"])
        }
    }

    private func sceneNightMode() {
        beginScene(2, "Night mode")
        step("Switching to Night mode",
             "Responders often work at night. The display button at the right switches between Match iPhone, Light and Night mode, and the app remembers the choice.",
             doing: "Tapping the display button and choosing Night mode.") {
            self.tap(self.app.buttons["Display"]); self.hold(1.2)
            self.tap(self.app.buttons["Night mode"])
        }
        say("Everything goes dark",
            "The map switches to its night style, and so do the sheets, the photo viewer and the Incidents tab. Light and dark mode both work everywhere in the app.",
            doing: "Night mode is on from here to the end of the video.")
    }

    /// Scenes 3, 4 and 5 all happen inside one incident's sheet.
    private func sceneIncidentSheet(details: Bool, drone: Bool, priority: Bool) {
        openIncident(containing: "FM 1570 south of Greenville", caption: details ? (
            "Opening an incident",
            "Tapping an incident zooms the map to it and slides up a details sheet that stops at half height.",
            "Tapping the red fire marker near Greenville.") : nil, scene: (3, "Incident details"))

        if details {
            say("The incident header",
                "At the top: the type, the place, a status badge, and a priority score from 0 to 100. Below that, how many reports came in, when the first one arrived, and how many photos and videos there are.",
                doing: "Reading the header of the sheet.")
            step("Expanding the sheet", "Dragging the handle up makes the sheet full height, with more room for details.",
                 doing: "Dragging the sheet up to full height.") {
                self.drag(from: (0.5, 0.49), to: (0.5, 0.10))
            }
            say("AI analysis",
                "This card shows what the computer vision found in all of this incident's photos and videos: fire, smoke, how many people, anyone who may be down, and whether dark pictures needed brightening. These are real results from the AI, not made up.",
                doing: "Looking at the AI analysis card.")

            let aiImage = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'AI view of'")).firstMatch
            if aiImage.waitForExistence(timeout: 5) {
                step("Seeing what the AI saw", "Each picture has boxes around what the AI detected: red for fire, gray for smoke, blue for people. Tapping one opens it full screen.",
                     doing: "Tapping an AI image.") {
                    self.tap(aiImage)
                }
                hold(3)
                let original = app.buttons["Original"]
                if original.waitForExistence(timeout: 3) {
                    step("Original versus AI view", "A switch at the top flips between the original photo and the AI view with its detection boxes.",
                         doing: "Tapping Original, then AI view again.") {
                        self.tap(original); self.hold(2.5)
                        self.tap(self.app.buttons["AI view"].firstMatch); self.hold(2)
                    }
                }
                tapIfExists(app.buttons["Done"], note: "Closing the viewer.")
                hold(1)
            }
        }

        if drone {
            let launch = app.buttons["launchDroneFeedButton"]
            step("Drone feed", "Once fire is confirmed, the sheet offers a drone feed so a responder can see the scene before arriving.",
                 doing: "Scrolling down to the Drone feed card.", scene: (4, "Drone feed")) {
                self.scrollSheet(until: launch)
            }
            step("Launching the feed",
                 "No drone is connected yet, so this plays simulated footage: recorded real wildfires, clearly labeled Simulated. The AI analysis of the video is real. When your drone is connected, the same card shows its live camera.",
                 doing: "Tapping Launch drone feed.") {
                self.tap(launch)
            }
            _ = app.descendants(matching: .any)["liveDroneFrame"].waitForExistence(timeout: 15)
            say("Live counts from the AI",
                "While it plays, the AI checks the video about two and a half times a second and counts people in view, people who may be lying on the ground and could be injured, people close to the flames, and how much of the picture is fire.",
                doing: "Watching the live numbers update.", extra: 3)
            say("People and fire", "The crew shows up first and is counted. When the video moves to the burning grass, the fire percentage rises.",
                doing: "Watching the feed continue.", extra: 6)
            let frame = app.descendants(matching: .any)["liveDroneFrame"]
            if frame.exists {
                step("Full screen", "Tapping the video opens it full screen with the numbers underneath.", doing: "Tapping the video.") {
                    self.tap(frame)
                }
                hold(5)
                tapIfExists(app.buttons["Done"], note: "Closing full screen.")
            }
            let stop = app.buttons["stopDroneFeedButton"]
            step("Stopping the feed", "The feed saved snapshots into the incident while it ran, and logged them in the timeline.",
                 doing: "Scrolling to Stop feed and tapping it.") {
                self.scrollSheet(until: stop)
                self.tap(stop)
            }
            hold(2)
            scrollSheetUp(0.25)
            say("Snapshots", "Under the card are the snapshots the feed saved, each with what the AI saw at that moment.",
                doing: "Looking at the saved snapshots.")
        }

        if priority {
            let why = app.staticTexts["Why this priority?"]
            step("Why this priority?",
                 "Every rule that added points is listed, so a responder or a judge can check the math: the incident type, fire confirmed by the AI, people, extra reports, and night time. It's simple rules, not a black box.",
                 doing: "Scrolling to Why this priority.", scene: (5, "Priority & actions")) {
                self.scrollSheet(until: why)
            }
            hold(1)
            scrollSheetUp(0.45)
            say("Photos and videos", "Everything residents uploaded for this incident. A small icon marks the pictures where the AI found something.",
                doing: "Looking at the media gallery.")
            scrollSheetUp(0.6)
            say("Timeline", "Every report, AI result, drone snapshot and status change, with times, so there is a record of what happened.",
                doing: "Scrolling through the timeline.")

            step("Responder actions", "These buttons are always at the bottom of the sheet. Mark responding turns the incident amber on the map and starts the response clock.",
                 doing: "Tapping Mark responding.") {
                self.tap(self.app.buttons["Mark responding"])
            }
            hold(2)
            step("Marking it resolved", "Resolving asks for a confirmation so nobody does it by accident. The incident turns gray.",
                 doing: "Tapping Mark resolved and confirming.") {
                self.tap(self.app.buttons["Mark resolved"].firstMatch); self.hold(1.5)
                let confirm = self.app.buttons.matching(NSPredicate(format: "label == 'Mark resolved'")).allElementsBoundByIndex.last
                if let confirm, confirm.exists { self.tap(confirm) }
            }
            hold(2)
            step("Reopening", "A resolved incident can be reopened. This puts the demo back as it was.", doing: "Tapping Reopen.") {
                self.tap(self.app.buttons["Reopen"])
            }
            hold(1.5)
        }

        closeSheet()
    }

    private func sceneSevereWeather() {
        beginScene(6, "Severe weather")
        step("Weather incidents",
             "The same map handles every kind of disaster. Switching to Severe weather only shows the tornado, the storm, the flooded crossing and the heavy rain.",
             doing: "Recentering the map, then choosing Severe weather only in the Type chip.") {
            self.tap(self.app.buttons["Recenter map"]); self.hold(1.5)
            self.tap(self.app.buttons["Incident type filter"]); self.hold(1.2)
            self.tap(self.app.buttons["Severe weather only"])
        }
        openIncident(containing: "FM 815 east of Leonard", caption: (
            "A tornado report",
            "Tapping the tornado opens its sheet.",
            "Tapping the tornado marker near Leonard."), scene: nil)
        drag(from: (0.5, 0.49), to: (0.5, 0.10))
        let why = app.staticTexts["Why this priority?"]
        scrollSheet(until: why)
        scrollSheetUp(0.3)
        say("Priority for weather",
            "A tornado starts with 40 points, more than most incidents. The AI can recognize flames, smoke and people but not a tornado, so weather reports are not marked down for missing AI proof. The number of independent reports counts instead.",
            doing: "Reading the priority breakdown.")
        closeSheet()
        step("Back to everything", "Returning the map to all incident types.", doing: "Choosing All incidents.") {
            self.tap(self.app.buttons["Incident type filter"]); self.hold(1.2)
            self.tap(self.app.buttons["All incidents"])
        }
    }

    private func sceneReport() {
        beginScene(7, "Reporting")
        step("Reporting an incident",
             "Any resident can report an emergency. This big button is the main action on the map.",
             doing: "Tapping Report incident.") {
            self.tap(self.app.buttons["reportIncidentButton"])
        }
        say("The 911 banner",
            "The form always starts with: in an emergency, call 911 first. RescueSight supports emergency services, it does not replace them. There is even a Call button.",
            doing: "Reading the banner at the top.")
        step("What's happening?",
             "Ten types in three groups: fire and smoke, severe weather, and medical and other. I'm choosing Fire.",
             doing: "Scrolling the type tiles and tapping Fire.") {
            self.scrollSheetUp(0.2)
            self.tap(self.app.buttons["Fire"].firstMatch)
        }

        let search = app.textFields["addressSearchField"]
        step("Searching an address",
             "You can type an address or place and pick a suggestion, and the pin jumps there. I'm typing Sherman, Texas.",
             doing: "Typing in the search box.") {
            self.scrollSheet(until: search, maxSwipes: 4)
            self.tap(search)
            search.typeText("Sherman, TX")
        }
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sherman, TX'")).firstMatch
        if suggestion.waitForExistence(timeout: 20) {
            step("Picking a suggestion", "Apple Maps finds the exact spot, the pin moves there, and the street name updates.",
                 doing: "Tapping the Sherman, TX suggestion.") {
                self.tap(suggestion)
            }
        } else {
            tapIfExists(app.buttons["Done"], note: "Closing the keyboard.")
        }
        hold(2)
        step("Using my location",
             "Normally the pin starts at your current location, and you can drag it to adjust. This button returns the pin to where the phone is. The simulator's location is set next to the Greenville fire.",
             doing: "Tapping the location button.") {
            self.scrollSheetUp(0.0)
            self.tap(self.app.buttons["Use my current location"])
        }
        let place = app.staticTexts["pinPlaceName"]
        _ = place.waitForExistence(timeout: 10)
        hold(2)

        step("Describing what you see", "A short description helps responders, with landmarks if possible.",
             doing: "Typing a description.") {
            let field = self.app.descendants(matching: .any)
                .matching(NSPredicate(format: "placeholderValue BEGINSWITH 'What do you see'")).firstMatch
            self.scrollSheet(until: field, maxSwipes: 7)
            self.tap(field)
            _ = self.app.keyboards.firstMatch.waitForExistence(timeout: 5)
            field.typeText("Flames getting close to the barn and smoke blowing across the road.")
            self.tapIfExists(self.app.buttons["Done"], note: "Closing the keyboard.")
        }

        step("Adding a photo",
             "On a real iPhone there are two buttons here: Take photo or video, which opens the camera, and Choose from library. The simulator has no camera, so I'm choosing a photo of the fire from the library.",
             doing: "Opening the photo library.") {
            let library = self.app.buttons["Choose from library"]
            self.scrollSheet(until: library, maxSwipes: 5)
            self.tap(library)
        }
        hold(1.5)
        let pickerPhotos = app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info'"))
        _ = pickerPhotos.firstMatch.waitForExistence(timeout: 10)
        emit(["k": "debug", "labels": pickerPhotos.allElementsBoundByIndex.map(\.label)])
        let label = environment["RS_PHOTO_LABEL"]  // e.g. "Photo, October 09, 7:07 AM"
        var photo = app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info' AND label BEGINSWITH 'Photo,'")).firstMatch
        if let label {
            let match = app.images.matching(NSPredicate(format: "identifier == 'PXGGridLayout-Info' AND label BEGINSWITH %@", label)).firstMatch
            if match.waitForExistence(timeout: 8) { photo = match }
        }
        if photo.waitForExistence(timeout: 10) {
            step("Choosing the photo", "I'm picking the photo of the grass fire.", doing: "Tapping the photo.") {
                self.tap(photo)
            }
        }
        _ = app.buttons["Remove"].waitForExistence(timeout: 15)
        hold(2)

        step("Sending the report", "The report goes to the server, which checks whether it matches an existing incident, and the AI starts analyzing the photo in the background.",
             doing: "Tapping Send report.") {
            self.scrollSheet(until: self.app.buttons["sendReportButton"], maxSwipes: 1)
            self.tap(self.app.buttons["sendReportButton"])
        }
        let toast = app.descendants(matching: .any)["reportSentToast"]
        _ = toast.waitForExistence(timeout: 20)
        // The message hides itself a few seconds after the AI answers, so tap
        // View while it is still showing and let the narration carry on.
        step("Merged, then the AI answers",
             "This is also a fire, within 300 meters and two hours of an open incident, so it joined that incident instead of making a duplicate dot. Seconds later the AI finishes and the same message shows what it found in the photo. Uploads never wait for the AI.",
             doing: "Reading the confirmation, then tapping View to open the incident.") {
            let answered = NSPredicate(format: "label CONTAINS 'AI found' OR label CONTAINS 'AI didn'")
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: answered, object: toast)], timeout: 12)
            self.hold(2.5)
            let view = self.app.buttons["View"]
            if view.exists {
                self.tap(view)
            } else {   // the message already closed: open the incident from its marker
                let marker = self.app.buttons.matching(NSPredicate(format: "label CONTAINS 'FM 1570 south of Greenville'")).firstMatch
                self.tap(marker)
            }
        }
        say("The incident, updated",
            "It now has one more report, and the new report and the AI's result are at the top of its timeline.",
            doing: "Scrolling down to the timeline.", hold: false)
        hold(1.5)
        drag(from: (0.5, 0.49), to: (0.5, 0.10))
        scrollSheet(until: app.staticTexts["Timeline"], maxSwipes: 8)
        hold(3)
        closeSheet()
    }

    private func sceneIncidentsTab() {
        beginScene(8, "Incidents tab")
        step("The responder view",
             "The second tab is for responders. The badge on the tab counts incidents that are active and high priority.",
             doing: "Tapping the Incidents tab.") {
            self.tap(self.app.tabBars.buttons["Incidents"])
        }
        _ = app.descendants(matching: .any)["kpi_active"].waitForExistence(timeout: 15)
        say("Four key numbers",
            "Active incidents, how many people the AI has detected at open incidents, how many incidents are still unverified by the AI, and the average time from the first report to a responder responding. Each is a simple count that can be checked.",
            doing: "Looking at the four cards at the top.", extra: 2)
        step("Sorted by priority",
             "Below, every incident is sorted by priority, highest first, with the score on the right and what the AI found. A responder knows where to go first.",
             doing: "Scrolling down the list.") {
            self.scrollPage(0.35)
        }
        hold(1)
        scrollPage(-0.35)

        let resolved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resolved ('")).firstMatch
        step("Filtering the list", "Open shows what still needs attention. Resolved shows what has been handled.",
             doing: "Tapping Resolved, then All, then Open.") {
            self.tap(resolved); self.hold(2.5)
            self.tap(self.app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All ('")).firstMatch); self.hold(2.5)
            self.tap(self.app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open ('")).firstMatch)
        }
        let first = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'incidentRow_'")).firstMatch
        step("Opening from the list", "Tapping a row opens the same details sheet as on the map.",
             doing: "Tapping the top incident.") {
            self.tap(first)
        }
        hold(4)
        // Close the sheet by dragging its handle down.
        drag(from: (0.5, 0.49), to: (0.5, 0.97), fast: true)
        hold(1)
        drag(from: (0.5, 0.49), to: (0.5, 0.97), fast: true)
        step("Back to the map", "The Map and Incidents tabs share the same data, so a change in one shows up in the other immediately.",
             doing: "Tapping the Map tab.") {
            self.tap(self.app.tabBars.buttons["Map"])
        }
    }

    // MARK: - Building blocks

    private func launchApp() {
        XCUIDevice.shared.location = XCUILocation(location: besideGreenvilleFire)
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["reportIncidentButton"].waitForExistence(timeout: 30),
                      "The map didn't load. Is the backend running?")
        hold(2)
    }

    /// Start a scene (numbered for the progress strip).
    private func beginScene(_ number: Int, _ title: String) {
        sceneNumber = number
        sceneTitle = title
    }

    /// Show a caption, then wait long enough to read it and for the voice-over to finish.
    private func say(_ headline: String, _ detail: String, doing: String, extra: Double = 0, hold shouldHold: Bool = true) {
        emit(["k": "cap", "scene": sceneNumber, "scene_title": sceneTitle,
              "headline": headline, "detail": detail, "doing": doing])
        if shouldHold { hold(readingTime(doing + " " + detail) + extra) }
    }

    /// Show a caption, do the action while the voice-over plays, then wait for the rest.
    private func step(_ headline: String, _ detail: String, doing: String, scene: (Int, String)? = nil,
                      actions: () -> Void) {
        if let scene { beginScene(scene.0, scene.1) }
        emit(["k": "cap", "scene": sceneNumber, "scene_title": sceneTitle,
              "headline": headline, "detail": detail, "doing": doing])
        let started = Date()
        actions()
        let remaining = readingTime(doing + " " + detail) - Date().timeIntervalSince(started)
        if remaining > 0 { hold(remaining) }
    }

    /// Seconds needed to read and hear this text (the voice speaks about 3 words a second).
    private func readingTime(_ text: String) -> Double {
        let words = Double(text.split(separator: " ").count)
        return max(3.0, words * 0.38 + 1.2)
    }

    private func hold(_ seconds: Double) {
        if !isFast { Thread.sleep(forTimeInterval: seconds) }
    }

    /// Tap an element and tell the video where, so it can draw a ring.
    private func tap(_ element: XCUIElement) {
        guard element.waitForExistence(timeout: 8) else {
            snapshot("after scene FAIL \(sceneNumber)")
            XCTFail("Couldn't find the element to tap: \(element)")
            return
        }
        let frame = element.frame
        emit(["k": "tap", "x": frame.midX, "y": frame.midY])
        element.tap()
    }

    private func tapIfExists(_ element: XCUIElement, note: String) {
        if element.waitForExistence(timeout: 3) { tap(element); hold(1) }
    }

    /// Drag from one spot to another (both as fractions of the screen) and tell the video.
    private func drag(from start: (Double, Double), to end: (Double, Double), fast: Bool = false) {
        let size = app.windows.firstMatch.frame.size
        emit(["k": "swipe", "x1": start.0 * size.width, "y1": start.1 * size.height,
              "x2": end.0 * size.width, "y2": end.1 * size.height])
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: start.0, dy: start.1))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: end.0, dy: end.1))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: fast ? .fast : .slow, thenHoldForDuration: 0.1)
        hold(1)
    }

    /// Scroll drags start in the narrow margin at the left edge, so they never
    /// land on a map inside the page (which would pan the map instead of scrolling).
    private static let edge = 0.025

    /// Scroll the content of an open sheet (finger moves up, content moves up).
    private func scrollSheetUp(_ amount: Double) {
        guard amount > 0 else { return }
        let start = 0.80
        drag(from: (Self.edge, start), to: (Self.edge, max(start - amount, 0.12)))
    }

    /// Scroll a sheet until an element is fully in view AND clear of the
    /// buttons pinned to the bottom (those are see-through, so an element
    /// behind them counts as "tappable" but a tap would hit the bar instead).
    private func scrollSheet(until element: XCUIElement, maxSwipes: Int = 8) {
        let height = app.windows.firstMatch.frame.height
        func isClear() -> Bool {
            element.exists && element.isHittable && element.frame.maxY < height * 0.84 && element.frame.minY > height * 0.10
        }
        var swipes = 0
        while !isClear() && swipes < maxSwipes {
            drag(from: (Self.edge, 0.80), to: (Self.edge, 0.45))
            swipes += 1
        }
    }

    /// Scroll a full-screen page (positive = down the page).
    private func scrollPage(_ amount: Double) {
        let from = amount > 0 ? 0.75 : 0.35
        drag(from: (0.5, from), to: (0.5, from - amount))
    }

    /// Open an incident from its marker on the map. `caption` explains it; `scene` starts a scene.
    private func openIncident(containing place: String,
                              caption: (String, String, String)?,
                              scene: (Int, String)?) {
        let marker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", place)).firstMatch
        let open = {
            if !marker.waitForExistence(timeout: 3) {   // off screen: show all of North Texas first
                self.tap(self.app.buttons["Recenter map"]); self.hold(1.5)
            }
            XCTAssertTrue(marker.waitForExistence(timeout: 10), "No map marker for \(place)")
            self.tap(marker)
            _ = self.app.staticTexts["AI analysis"].waitForExistence(timeout: 10)
        }
        if let scene { beginScene(scene.0, scene.1) }
        if let caption {
            step(caption.0, caption.1, doing: caption.2, actions: open)
        } else {
            open()
        }
        hold(1)
    }

    /// Close a details sheet by dragging it down (large -> half -> gone).
    private func closeSheet() {
        for _ in 0..<2 {
            drag(from: (0.5, 0.075), to: (0.5, 0.99), fast: true)
            if app.buttons["reportIncidentButton"].isHittable { break }
        }
        hold(1)
    }

    /// One line of JSON, appended to the events file (and printed as a backup).
    private func emit(_ fields: [String: Any]) {
        var line = fields
        line["t"] = Date().timeIntervalSince1970
        guard let data = try? JSONSerialization.data(withJSONObject: line),
              var text = String(data: data, encoding: .utf8) else { return }
        text += "\n"
        print("RSEVT \(text)", terminator: "")
        if let handle = FileHandle(forWritingAtPath: eventsPath) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: eventsPath, contents: Data(text.utf8))
        }
    }
}
