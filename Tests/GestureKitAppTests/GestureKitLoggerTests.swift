import Foundation
@testable import GestureKitApp
import XCTest

final class GestureKitLoggerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GestureKitLoggerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDefaultTerminalOutputSuppressesInfoButWritesFile() throws {
        let logURL = temporaryDirectory.appendingPathComponent("GestureKitApp.log")
        var terminalLines: [String] = []
        let logger = GestureKitLogger(
            debugEnabled: false,
            logFileURL: logURL,
            terminalWriter: { terminalLines.append($0) }
        )

        logger.info("gesture_published gesture=three_finger_tap connections=1")

        XCTAssertTrue(terminalLines.isEmpty)
        XCTAssertTrue(try String(contentsOf: logURL, encoding: .utf8).contains("gesture_published"))
    }

    func testDefaultTerminalOutputIncludesWarnings() {
        let logURL = temporaryDirectory.appendingPathComponent("GestureKitApp.log")
        var terminalLines: [String] = []
        let logger = GestureKitLogger(
            debugEnabled: false,
            logFileURL: logURL,
            terminalWriter: { terminalLines.append($0) }
        )

        logger.warn("gesture_published_without_client connections=0")

        XCTAssertEqual(terminalLines.count, 1)
        XCTAssertTrue(terminalLines[0].contains("level=warn"))
    }

    func testSelectedInfoCanBeWrittenToTerminal() {
        let logURL = temporaryDirectory.appendingPathComponent("GestureKitApp.log")
        var terminalLines: [String] = []
        let logger = GestureKitLogger(
            debugEnabled: false,
            logFileURL: logURL,
            terminalWriter: { terminalLines.append($0) }
        )

        logger.info("app_started", terminal: true)

        XCTAssertEqual(terminalLines.count, 1)
        XCTAssertTrue(terminalLines[0].contains("app_started"))
    }

    func testDebugTerminalOutputIncludesDebugLines() {
        let logURL = temporaryDirectory.appendingPathComponent("GestureKitApp.log")
        var terminalLines: [String] = []
        let logger = GestureKitLogger(
            debugEnabled: true,
            logFileURL: logURL,
            terminalWriter: { terminalLines.append($0) }
        )

        logger.debug("gesture_unstable duration_ms=10")

        XCTAssertEqual(terminalLines.count, 1)
        XCTAssertTrue(terminalLines[0].contains("gesture_unstable"))
    }

    func testDebugTerminalOutputFollowsDynamicProvider() {
        let logURL = temporaryDirectory.appendingPathComponent("GestureKitApp.log")
        var terminalLines: [String] = []
        var enabled = false
        let logger = GestureKitLogger(
            debugEnabled: nil,
            debugEnabledProvider: { enabled },
            logFileURL: logURL,
            terminalWriter: { terminalLines.append($0) }
        )

        logger.debug("diagnostic_frame gesture=three_finger_tap")
        XCTAssertTrue(terminalLines.isEmpty)

        enabled = true
        logger.debug("diagnostic_frame gesture=three_finger_tap")

        XCTAssertEqual(terminalLines.count, 1)
        XCTAssertTrue(terminalLines[0].contains("diagnostic_frame"))
    }
}
