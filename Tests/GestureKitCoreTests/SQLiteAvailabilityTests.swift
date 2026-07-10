import XCTest
@testable import GestureKitCore

final class SQLiteAvailabilityTests: XCTestCase {
    func testSQLiteVersionIsAvailable() throws {
        XCTAssertFalse(try sqliteVersion().isEmpty)
    }
}
