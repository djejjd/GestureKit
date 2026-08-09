import AppKit

/// 菜单栏图标。
///
/// svg 内容直接内嵌为常量：SPM 生成的 `Bundle.module` 资源访问器只认 `.app` 根目录的
/// bundle 或硬编码的 `.build` 路径，打包成 `.app` 后从 Resources 加载不可靠（脱离构建树
/// 会在启动瞬间崩溃）。341B 的图标内嵌成本可忽略，且 `swift run` 与 `.app` 两种形态都稳定。
enum MenuBarIcon {
    static let svgData = Data("""
    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">
      <rect x="2" y="4" width="14" height="10" rx="3" ry="3" fill="none" stroke="black" stroke-width="1.5"/>
      <circle cx="5" cy="11" r="1.5" fill="black"/>
      <circle cx="9" cy="11" r="1.5" fill="black"/>
      <circle cx="13" cy="11" r="1.5" fill="black"/>
    </svg>
    """.utf8)

    /// 以菜单栏尺寸构造图标；失败时返回 nil（调用方自行决定是否跳过图标）。
    static func image(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage? {
        guard let icon = NSImage(data: svgData) else { return nil }
        icon.size = size
        return icon
    }
}
