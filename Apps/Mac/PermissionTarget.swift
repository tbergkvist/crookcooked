import Foundation

/// The System Settings panes macOS exposes for the permissions this app needs.
/// Sending someone straight to the right pane is the difference between a
/// permission being granted and being given up on.
enum PermissionTarget: String, CaseIterable, Identifiable {
    case camera
    case inputMonitoring
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "camera"
        case .inputMonitoring: return "input monitoring"
        case .accessibility: return "accessibility"
        }
    }

    var why: String {
        switch self {
        case .camera: return "Scene changes and evidence photos"
        case .inputMonitoring: return "Keyboard and pointer tampering"
        case .accessibility: return "Fallback lock when the login service is unavailable"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .inputMonitoring: return "cursorarrow.motionlines"
        case .accessibility: return "accessibility"
        }
    }

    var settingsURL: String {
        switch self {
        case .camera:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .inputMonitoring:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}
