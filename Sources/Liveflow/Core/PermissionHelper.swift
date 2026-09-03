import AppKit
import CoreGraphics

public enum PermissionHelper {
    public static var hasScreenRecordingPermission: Bool {
        return CGPreflightScreenCaptureAccess()
    }

    public static func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    public static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
