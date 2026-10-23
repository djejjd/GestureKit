import XCTest
@testable import GestureKitApp

final class DragInputShieldTests: XCTestCase {
    func testOrdinaryMouseSequencePassesWithoutCandidate() {
        var shield = DragInputShieldState()
        for event in [ShieldMouseEvent.down, .dragged, .up] {
            XCTAssertFalse(shield.suppress(event, now: 0))
        }
    }

    func testCandidateSuppressesOwnedDownDragAndUp() {
        var shield = DragInputShieldState()
        XCTAssertTrue(shield.arm(sessionID: "swipe", now: 0))
        XCTAssertTrue(shield.suppress(.down, now: 10))
        XCTAssertTrue(shield.suppress(.dragged, now: 20))
        XCTAssertTrue(shield.suppress(.up, now: 30))
        shield.cancel()
        XCTAssertFalse(shield.suppress(.down, now: 31))
        XCTAssertNil(shield.sessionID)
    }

    func testExistingMouseDragKeepsItsPairedUp() {
        var shield = DragInputShieldState()
        XCTAssertFalse(shield.suppress(.down, now: 0))
        XCTAssertTrue(shield.arm(sessionID: "swipe", now: 1))
        XCTAssertFalse(shield.suppress(.dragged, now: 2))
        XCTAssertFalse(shield.suppress(.up, now: 3))
        XCTAssertTrue(shield.suppress(.down, now: 4))
    }

    func testLeaseExpiresEvenWithoutFramesOrRelease() {
        var shield = DragInputShieldState()
        _ = shield.arm(sessionID: "swipe", now: 0)
        XCTAssertTrue(shield.suppress(.down, now: 1))
        XCTAssertFalse(shield.suppress(.dragged, now: 800))
        XCTAssertNil(shield.sessionID)
        XCTAssertFalse(shield.suppress(.up, now: 801))
        XCTAssertTrue(shield.arm(sessionID: "next", now: 900))
        XCTAssertTrue(shield.suppress(.down, now: 901))
    }

    func testFinishCoversDelayedSystemDownButDoesNotExtendLease() {
        var shield = DragInputShieldState()
        _ = shield.arm(sessionID: "swipe", now: 0)
        shield.finish(sessionID: "swipe", now: 100)
        XCTAssertTrue(shield.suppress(.down, now: 110))
        XCTAssertTrue(shield.suppress(.up, now: 120))
        XCTAssertFalse(shield.suppress(.down, now: 220))
        XCTAssertNil(shield.sessionID)
        _ = shield.arm(sessionID: "next", now: 1000)
        shield.finish(sessionID: "next", now: 1790)
        XCTAssertFalse(shield.suppress(.down, now: 1800))
    }

    func testFinishDoesNotDropOwnedMouseUpBeforeDeadline() {
        var shield = DragInputShieldState()
        _ = shield.arm(sessionID: "swipe", now: 0)
        XCTAssertTrue(shield.suppress(.down, now: 5))
        shield.finish(sessionID: "swipe", now: 100)
        XCTAssertTrue(shield.suppress(.dragged, now: 300))
        XCTAssertTrue(shield.suppress(.up, now: 400))
        XCTAssertNil(shield.sessionID)
        XCTAssertFalse(shield.suppress(.down, now: 401))
    }

    func testStaleAndRepeatedFinishCannotReleaseOrExtendNewSession() {
        var shield = DragInputShieldState()
        _ = shield.arm(sessionID: "first", now: 0)
        shield.finish(sessionID: "first", now: 20)
        shield.finish(sessionID: "first", now: 100)
        XCTAssertFalse(shield.suppress(.down, now: 140))
        XCTAssertFalse(shield.suppress(.up, now: 150))
        _ = shield.arm(sessionID: "second", now: 200)
        shield.finish(sessionID: "first", now: 210)
        XCTAssertEqual(shield.sessionID, "second")
        XCTAssertTrue(shield.suppress(.down, now: 400))
    }

    func testDuplicateArmCannotRenewExpiredCandidate() {
        var shield = DragInputShieldState()
        _ = shield.arm(sessionID: "swipe", now: 0)
        XCTAssertFalse(shield.arm(sessionID: "swipe", now: 700))
        XCTAssertFalse(shield.suppress(.down, now: 800))
    }

    func testCancelRestoresInputAndNextOperation() {
        var shield = DragInputShieldState()
        _ = shield.arm(sessionID: "first", now: 0)
        XCTAssertTrue(shield.suppress(.down, now: 1))
        shield.cancel()
        shield.cancel()
        XCTAssertNil(shield.sessionID)
        XCTAssertFalse(shield.suppress(.up, now: 10))
        XCTAssertTrue(shield.arm(sessionID: "next", now: 20))
        XCTAssertTrue(shield.suppress(.down, now: 21))
    }
}
