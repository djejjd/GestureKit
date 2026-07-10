import CSQLite

/// SQLite 运行时不可用时抛出的错误。
public enum SQLiteAvailabilityError: Error {
    case versionUnavailable
}

/// 返回当前链接的 SQLite 运行时版本，用于启动前能力探测。
public func sqliteVersion() throws -> String {
    guard let version = sqlite3_libversion() else {
        throw SQLiteAvailabilityError.versionUnavailable
    }
    return String(cString: version)
}
