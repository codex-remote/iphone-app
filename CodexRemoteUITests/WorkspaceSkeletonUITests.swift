import XCTest

final class WorkspaceSkeletonUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSidebarButtonTogglesProjectManager() throws {
        let app = launchApp()
        let toggle = button("workspace.sidebar.toggle", in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))

        toggle.tap()
        XCTAssertTrue(element("projectManager.drawer", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(element("project.project_codexremote", in: app).waitForExistence(timeout: 2))

        toggle.tap()
        XCTAssertFalse(element("projectManager.drawer", in: app).waitForExistence(timeout: 1))
    }

    func testProjectManagerShowsLoadingUntilProjectsArrive() throws {
        let app = launchApp(arguments: ["--demo-drawer", "--demo-project-loading"])
        let loading = element("projectManager.projects.loading", in: app)

        XCTAssertTrue(loading.waitForExistence(timeout: 4))
        XCTAssertFalse(element("project.project_codexremote", in: app).exists)
        XCTAssertTrue(element("project.project_codexremote", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(loading.waitForNonExistence(timeout: 2))
    }

    func testOfflineMacAgentDoesNotShowProjectLoading() throws {
        let app = launchApp(arguments: ["--demo-drawer", "--demo-offline"])

        XCTAssertTrue(app.staticTexts["Connect your Mac Agent to load projects."].waitForExistence(timeout: 4))
        XCTAssertFalse(element("projectManager.projects.loading", in: app).exists)
    }

    func testNewSessionCanChooseProject() throws {
        let app = launchApp()
        let newSession = button("workspace.newSession", in: app)
        XCTAssertTrue(newSession.waitForExistence(timeout: 4))

        newSession.tap()
        let newSessionNavigation = app.navigationBars["New session"]
        XCTAssertTrue(newSessionNavigation.waitForExistence(timeout: 2))

        let project = button("newSession.project.project_orders", in: app)
        XCTAssertTrue(project.waitForExistence(timeout: 2))
        project.tap()

        let prompt = element("composer.prompt", in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        XCTAssertNotEqual(stringValue(of: prompt), "Review the current changes, fix any issues, and run the relevant tests.")
        XCTAssertFalse(button("composer.primaryAction", in: app).isEnabled)
        XCTAssertTrue(app.staticTexts["orders-api"].waitForExistence(timeout: 3))
        XCTAssertTrue(newSessionNavigation.waitForNonExistence(timeout: 1))
    }

    func testRestrictedExecutionIsVisibleBeforeStartingTask() throws {
        let app = launchApp(arguments: ["--reset-execution-profiles"])
        let banner = button("execution.restricted.banner", in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: 4))

        banner.tap()
        XCTAssertTrue(app.navigationBars["Execution access"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Control Xcode devices"].waitForExistence(timeout: 2))
        let approvalPolicy = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "never")).firstMatch
        XCTAssertTrue(approvalPolicy.waitForExistence(timeout: 2))
    }

    func testSessionSelectionClosesProjectManagerAndButtonCanReopenIt() throws {
        let app = launchApp(arguments: ["--demo-drawer"])
        XCTAssertTrue(element("projectManager.drawer", in: app).waitForExistence(timeout: 4))

        let thread = button("thread.project_codexremote.thread_recent", in: app)
        XCTAssertTrue(thread.waitForExistence(timeout: 3))
        thread.tap()

        XCTAssertTrue(app.staticTexts["Fix Relay reconnect policy"].waitForExistence(timeout: 2))
        XCTAssertFalse(element("projectManager.drawer", in: app).waitForExistence(timeout: 1))

        let toggle = button("workspace.sidebar.toggle", in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.tap()
        XCTAssertTrue(element("projectManager.drawer", in: app).waitForExistence(timeout: 2))
    }

    func testTappingWorkspaceClosesProjectManager() throws {
        let app = launchApp(arguments: ["--demo-drawer"])
        let drawer = element("projectManager.drawer", in: app)
        XCTAssertTrue(drawer.waitForExistence(timeout: 4))

        let visibleWorkspaceSliver = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.50))
        visibleWorkspaceSliver.tap()

        XCTAssertFalse(drawer.waitForExistence(timeout: 1))
        XCTAssertTrue(button("workspace.sidebar.toggle", in: app).waitForExistence(timeout: 2))
    }

    func testSessionSelectionLoadsPersistedHistoryIntoActivity() throws {
        let app = launchApp(arguments: ["--demo-drawer"])
        XCTAssertTrue(element("projectManager.drawer", in: app).waitForExistence(timeout: 4))

        let thread = button("thread.project_codexremote.thread_recent", in: app)
        XCTAssertTrue(thread.waitForExistence(timeout: 3))
        thread.tap()

        XCTAssertTrue(element("thread.detail", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("thread.detail.message.user", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Review the reconnect behavior."].waitForExistence(timeout: 3))
        XCTAssertTrue(element("thread.detail.message.assistant", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The reconnect transition is corrected and tests pass."].waitForExistence(timeout: 3))

        let processToggle = element("thread.detail.process.toggle", in: app)
        XCTAssertTrue(processToggle.waitForExistence(timeout: 3))
        processToggle.tap()
        XCTAssertTrue(element("thread.detail.process.items", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Checked the reconnect state machine and found a stale transition."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Ran xcodebuild build"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Build succeeded."].exists)
    }

    func testActivityUsesLatestMessagePreview() throws {
        let app = launchApp(arguments: ["--demo-drawer"])
        let activity = button("projectManager.activity", in: app)
        XCTAssertTrue(activity.waitForExistence(timeout: 4))
        activity.tap()

        XCTAssertTrue(app.staticTexts["The reconnect transition is corrected and tests pass."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Review the reconnect behavior"].exists)
    }

    func testLongSessionLoadsTranscriptInBoundedPages() throws {
        let app = launchApp(arguments: ["--demo-drawer", "--demo-long-history"])
        let thread = button("thread.project_codexremote.thread_recent", in: app)
        XCTAssertTrue(thread.waitForExistence(timeout: 4))
        thread.tap()

        let transcript = element("thread.detail", in: app)
        XCTAssertTrue(transcript.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue("30", of: transcript))
        XCTAssertFalse(app.staticTexts["Long history prompt 1"].exists)

        let loadEarlier = button("thread.detail.loadEarlier", in: app)
        XCTAssertTrue(loadEarlier.waitForExistence(timeout: 2))
        loadEarlier.tap()

        XCTAssertTrue(waitForValue("60", of: element("thread.detail", in: app)))
        XCTAssertTrue(app.staticTexts["Long history prompt 91"].waitForExistence(timeout: 2))
        XCTAssertFalse(button("thread.detail.loadEarlier", in: app).exists)

        let laterResponse = app.staticTexts["Long history response 113"]
        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.68))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.24))
        for _ in 0..<8 where !laterResponse.exists {
            scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
        }
        XCTAssertTrue(laterResponse.waitForExistence(timeout: 2))
    }

    func testLeadingSwipeReopensProjectManagerAfterOpeningSession() throws {
        let app = launchApp(arguments: ["--demo-drawer"])
        let drawer = element("projectManager.drawer", in: app)
        XCTAssertTrue(drawer.waitForExistence(timeout: 4))

        let thread = button("thread.project_codexremote.thread_recent", in: app)
        XCTAssertTrue(thread.waitForExistence(timeout: 3))
        thread.tap()
        XCTAssertFalse(drawer.waitForExistence(timeout: 1))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.50))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.76, dy: 0.50))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(drawer.waitForExistence(timeout: 2))
    }

    func testProjectManagerListCanScrollToMoreProjects() throws {
        let app = launchApp(arguments: ["--demo-drawer"])
        XCTAssertTrue(element("projectManager.drawer", in: app).waitForExistence(timeout: 4))

        let labProject = element("project.project_lab", in: app)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.62))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.32))
        for _ in 0..<6 where !labProject.exists {
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        XCTAssertTrue(labProject.waitForExistence(timeout: 2))
    }

    func testExpandedProjectShowsMoreThanFiveSessions() throws {
        let app = launchApp(arguments: ["--demo-drawer"])
        XCTAssertTrue(element("projectManager.drawer", in: app).waitForExistence(timeout: 4))

        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.62))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.32))
        let sixthThread = button("thread.project_codexremote.thread_extra_6", in: app)
        for _ in 0..<4 where !sixthThread.exists {
            scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
        }

        XCTAssertTrue(sixthThread.waitForExistence(timeout: 2))
    }

    func testExpandingLowerProjectScrollsItIntoFocus() throws {
        let app = launchApp(arguments: ["--demo-drawer"])
        XCTAssertTrue(element("projectManager.drawer", in: app).waitForExistence(timeout: 4))

        let activeProject = button("project.project_codexremote", in: app)
        XCTAssertTrue(activeProject.waitForExistence(timeout: 2))
        activeProject.tap()

        let lowerProject = button("project.project_lab", in: app)
        XCTAssertTrue(lowerProject.waitForExistence(timeout: 2))
        lowerProject.tap()

        let firstSession = button("thread.project_lab.thread_lab_1", in: app)
        XCTAssertTrue(firstSession.waitForExistence(timeout: 2))
        XCTAssertTrue(firstSession.isHittable)
        XCTAssertLessThan(lowerProject.frame.minY, app.frame.height * 0.55)
    }

    func testConnectionProfilesUseDifferentDefaultPorts() throws {
        let app = launchApp(arguments: ["--demo-settings", "--reset-connection-settings"])
        let urlField = app.textFields["connection.url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 4))
        XCTAssertTrue(stringValue(of: urlField).contains(":18767/"))

        let profilePicker = app.segmentedControls["connection.profile"]
        XCTAssertTrue(profilePicker.waitForExistence(timeout: 2))
        profilePicker.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(stringValue(of: urlField).contains(":18768/"))

        profilePicker.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(stringValue(of: urlField).contains(":18767/"))
    }

    func testRelayURLLaunchArgumentConfiguresIPhoneConnection() throws {
        let relayURL = "ws://192.0.2.10:18768/ws/app"
        let app = launchApp(arguments: [
            "--demo-settings",
            "--reset-connection-settings",
            "--relay-url", relayURL
        ])

        let urlField = app.textFields["connection.url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 4))
        XCTAssertEqual(stringValue(of: urlField), relayURL)

        let connectionToggle = element("connection.toggle", in: app)
        XCTAssertTrue(connectionToggle.waitForExistence(timeout: 2))
        XCTAssertEqual(stringValue(of: connectionToggle), "1")
    }

    func testConnectionToggleDisconnectsAndRunsFreshCheck() throws {
        let app = launchApp(arguments: ["--demo-settings", "--reset-connection-settings"])
        let connectionToggle = element("connection.toggle", in: app)
        XCTAssertTrue(connectionToggle.waitForExistence(timeout: 4))
        XCTAssertEqual(stringValue(of: connectionToggle), "1")

        connectionToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.50)).tap()
        XCTAssertTrue(waitForValue("0", of: connectionToggle))
        XCTAssertTrue(element("connection.status.offline", in: app).waitForExistence(timeout: 2))

        connectionToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.50)).tap()
        XCTAssertTrue(element("connection.status.connected", in: app).waitForExistence(timeout: 3))
        let reconnectedToggle = element("connection.toggle", in: app)
        XCTAssertTrue(waitForValue("1", of: reconnectedToggle))
    }

    func testComposerExposesVoiceInputWithoutReplacingSendAction() throws {
        let app = launchApp()
        let newTask = button("workspace.newTask", in: app)
        XCTAssertTrue(newTask.waitForExistence(timeout: 4))
        newTask.tap()

        let voiceInput = button("composer.voiceInput", in: app)
        XCTAssertTrue(voiceInput.waitForExistence(timeout: 4))
        XCTAssertTrue(voiceInput.isEnabled)
        XCTAssertEqual(stringValue(of: voiceInput), "Not recording")
        XCTAssertTrue(button("composer.primaryAction", in: app).waitForExistence(timeout: 2))
    }

    func testComposerKeepsTypedDraftAndDismissesKeyboardWhenTranscriptIsTapped() throws {
        let app = launchApp(arguments: ["--demo-project"])
        let newTask = button("workspace.newTask", in: app)
        XCTAssertTrue(newTask.waitForExistence(timeout: 4))
        newTask.tap()

        let prompt = element("composer.prompt", in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        XCTAssertFalse(button("composer.primaryAction", in: app).isEnabled)
        prompt.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        let expectedPrompt = "Keep this local draft."
        prompt.typeText(expectedPrompt)
        XCTAssertEqual(stringValue(of: prompt), expectedPrompt)
        XCTAssertFalse(app.buttons["Done"].exists)
        XCTAssertFalse(element("composer.dismissKeyboard", in: app).exists)

        let transcript = element("task.transcriptScroll", in: app)
        XCTAssertTrue(transcript.waitForExistence(timeout: 2))
        transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.16)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
        XCTAssertEqual(stringValue(of: prompt), expectedPrompt)

        let send = button("composer.primaryAction", in: app)
        XCTAssertTrue(send.isEnabled)
        XCTAssertEqual(send.label, "Start turn")
        send.tap()
        XCTAssertTrue(app.staticTexts[expectedPrompt].waitForExistence(timeout: 4))
    }

    func testTranscriptControlDismissesKeyboardWithoutLosingItsAction() throws {
        let app = launchApp(arguments: ["--demo-drawer", "--demo-long-history"])
        let thread = button("thread.project_codexremote.thread_recent", in: app)
        XCTAssertTrue(thread.waitForExistence(timeout: 4))
        thread.tap()

        let prompt = element("composer.prompt", in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        let processToggle = button("thread.detail.process.toggle", in: app)
        XCTAssertTrue(processToggle.waitForExistence(timeout: 3))
        processToggle.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
        XCTAssertTrue(element("thread.detail.process.items", in: app).waitForExistence(timeout: 2))
    }

    func testComposerSelectsProjectExecutionProfileBeforeTurn() throws {
        let app = launchApp(arguments: ["--reset-execution-profiles"])
        let newTask = button("workspace.newTask", in: app)
        XCTAssertTrue(newTask.waitForExistence(timeout: 4))
        newTask.tap()

        let profile = button("composer.executionProfile", in: app)
        XCTAssertTrue(profile.waitForExistence(timeout: 4))
        XCTAssertEqual(stringValue(of: profile), "Workspace access")
        profile.tap()

        let fullAccess = app.buttons["Full access"].firstMatch
        XCTAssertTrue(fullAccess.waitForExistence(timeout: 2))
        fullAccess.tap()
        XCTAssertEqual(stringValue(of: button("composer.executionProfile", in: app)), "Full access")
    }

    func testSubmittingTurnStreamsAssistantAndToolItemsInPlace() throws {
        let app = launchApp(arguments: ["--demo-project"])
        let newTask = button("workspace.newTask", in: app)
        XCTAssertTrue(newTask.waitForExistence(timeout: 4))
        newTask.tap()

        let prompt = element("composer.prompt", in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.tap()
        prompt.typeText("Review current changes.")

        let send = button("composer.primaryAction", in: app)
        XCTAssertTrue(send.waitForExistence(timeout: 3))
        XCTAssertTrue(send.isEnabled)
        send.tap()

        let processToggle = element("turn.live.process.toggle", in: app)
        XCTAssertTrue(processToggle.waitForExistence(timeout: 4))
        XCTAssertFalse(element("turn.live.process.items", in: app).exists)
        XCTAssertLessThanOrEqual(processToggle.frame.height, 40)
        XCTAssertTrue(element("turn.live.assistant", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["I found the reconnect state transition that needed correction. The focused tests pass and the change is ready for review."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start turn"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("turn.terminalNotice", in: app).exists)
        XCTAssertFalse(app.staticTexts["Turn completed"].exists)
        XCTAssertFalse(app.staticTexts["Build succeeded."].exists)

        processToggle.tap()
        XCTAssertTrue(element("turn.live.process.items", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Ran xcodebuild -scheme CodexRemote build"].waitForExistence(timeout: 2))
    }

    func testInterruptedTurnUsesCompactTerminalNotice() throws {
        let app = launchApp(arguments: ["--demo-project", "--demo-slow-turn"])
        let newTask = button("workspace.newTask", in: app)
        XCTAssertTrue(newTask.waitForExistence(timeout: 4))
        newTask.tap()

        let prompt = element("composer.prompt", in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.tap()
        prompt.typeText("Stop this test turn.")
        button("composer.primaryAction", in: app).tap()

        let interrupt = app.buttons["Interrupt current turn"]
        XCTAssertTrue(interrupt.waitForExistence(timeout: 3))
        interrupt.tap()

        let notice = element("turn.terminalNotice", in: app)

        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(notice.frame.height, 72)
        XCTAssertTrue(app.staticTexts["Turn interrupted"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Codex stopped cleanly."].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["0 files"].exists)
    }

    func testSubmittingFromExistingSessionKeepsHistoryScrollable() throws {
        let app = launchApp(arguments: ["--demo-drawer", "--demo-long-history"])
        let thread = button("thread.project_codexremote.thread_recent", in: app)
        XCTAssertTrue(thread.waitForExistence(timeout: 4))
        thread.tap()

        let prompt = element("composer.prompt", in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.tap()
        prompt.typeText("Continue this review.")
        let send = button("composer.primaryAction", in: app)
        XCTAssertTrue(send.waitForExistence(timeout: 3))
        XCTAssertTrue(send.isEnabled)
        send.tap()

        XCTAssertTrue(app.staticTexts["Continue this review."].waitForExistence(timeout: 3))
        let olderResponse = app.staticTexts["Long history response 116"]
        XCTAssertFalse(olderResponse.isHittable)

        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.38))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.78))
        for _ in 0..<5 where !olderResponse.isHittable {
            scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
        }

        XCTAssertTrue(waitUntilHittable(olderResponse, timeout: 3))
        XCTAssertTrue(app.staticTexts["Continue this review."].exists)
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--demo-idle"] + arguments
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func button(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons[identifier].firstMatch
    }

    private func stringValue(of element: XCUIElement) -> String {
        element.value as? String ?? ""
    }

    private func waitForValue(_ value: String, of element: XCUIElement, timeout: TimeInterval = 2) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 2) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
