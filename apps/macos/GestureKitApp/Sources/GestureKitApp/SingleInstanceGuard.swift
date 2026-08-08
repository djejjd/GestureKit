import Foundation

/// 单实例保护：通过 flock 文件锁检测是否已有 GestureKitApp 在运行。
///
/// GestureKitApp 是菜单栏应用，"关闭控制中心窗口"不会退出进程；重复启动时
/// 若旧实例仍在，新实例会并存两个实例，互相抢 IPC 端口与触控板监听。
/// 用 flock 独占文件锁（比端口探测可靠：无 TIME_WAIT/启动竞态），
/// 首次实例获取锁并持有到退出；重复实例获取失败即退出。
enum SingleInstanceGuard {
    /// 锁文件路径（tmp 域，重启/清理后自然失效）。
    private static let lockPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("gesturekit-app.lock")
        .path

    /// 尝试获取单实例独占锁。返回锁的 fd（须由调用方持有到进程退出并 close）；
    /// 返回 nil 表示已有实例在运行（锁被其他进程持有）。
    static func acquireLock() -> Int32? {
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }
        return fd
    }

    /// 释放锁（进程退出时调用）。
    static func releaseLock(fd: Int32?) {
        guard let fd else { return }
        flock(fd, LOCK_UN)
        close(fd)
    }
}
