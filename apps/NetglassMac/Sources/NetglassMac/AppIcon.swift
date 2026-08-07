import AppKit

/// App icons for history rows, resolved from the executable path (walks up to
/// the nearest `.app` bundle so NSWorkspace returns the real app icon) and
/// cached by path. Main-actor only: NSWorkspace + NSImage cache.
@MainActor
enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(forProcessPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let iconPath = bundlePath(forExecutable: path) ?? path
        let icon = NSWorkspace.shared.icon(forFile: iconPath)
        cache[path] = icon
        return icon
    }

    /// Nearest enclosing `.app` bundle for an executable, nil if none.
    /// Pure helper so bundle resolution is unit-testable without the UI.
    static func bundlePath(forExecutable executablePath: String) -> String? {
        var dir = (executablePath as NSString).deletingLastPathComponent
        while !dir.isEmpty && dir != "/" {
            if dir.hasSuffix(".app") { return dir }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }
}
