import AppKit
import Foundation
import OSLog

@MainActor
final class CrookcookedWallpaperService {
    private enum Variant: String {
        case armed
        case attention

        var artworkVariant: LockScreenArtwork.Variant {
            switch self {
            case .armed: return .armed
            case .attention: return .attention
            }
        }
    }

    private struct OriginalDesktop {
        let screen: NSScreen
        let imageURL: URL
        let options: [NSWorkspace.DesktopImageOptionKey: Any]
    }

    private var originals: [OriginalDesktop] = []
    private var active = false
    private var currentVariant: Variant = .armed
    private var attentionRevision = 0
    /// Mirrors the owner's alarm setting so the wallpaper states the real consequence.
    private var audibleAlarm = true
    private var showAvatar = true
    private let logger = Logger(subsystem: "app.crookcooked.mac.local", category: "CrookcookedWallpaper")

    func setAudibleAlarm(_ enabled: Bool) {
        guard enabled != audibleAlarm else { return }
        audibleAlarm = enabled
        redrawCurrent()
    }

    func setShowAvatar(_ enabled: Bool) {
        guard enabled != showAvatar else { return }
        showAvatar = enabled
        redrawCurrent()
    }

    private func redrawCurrent() {
        guard active else { return }
        let screens = originals.isEmpty ? NSScreen.screens : originals.map(\.screen)
        try? apply(currentVariant, to: screens, mugshot: nil)
    }

    @discardableResult
    func prepare() -> Bool {
        do {
            for screen in NSScreen.screens {
                // Only the armed face animates, so only it needs a frame set.
                _ = try renderWallpaper(for: screen, variant: .armed, mugshot: nil, cacheTag: nil)
                _ = try renderWallpaper(for: screen, variant: .attention, mugshot: nil, cacheTag: nil)
            }
            logger.info("Crookcooked wallpapers rendered for \(NSScreen.screens.count) display(s)")
            return true
        } catch {
            logger.error("Crookcooked wallpaper render failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func activate() throws {
        guard !active else { return }
        let workspace = NSWorkspace.shared
        originals = NSScreen.screens.compactMap { screen in
            guard let imageURL = workspace.desktopImageURL(for: screen) else { return nil }
            return OriginalDesktop(
                screen: screen,
                imageURL: imageURL,
                options: workspace.desktopImageOptions(for: screen) ?? [:]
            )
        }

        do {
            try apply(.armed, to: NSScreen.screens, mugshot: nil)
            currentVariant = .armed
            active = true
            logger.info("Crookcooked wallpaper activated on \(NSScreen.screens.count) display(s)")
        } catch {
            restore()
            throw error
        }
    }

    /// Best-effort live update. macOS owns the secure login UI; this only changes
    /// its wallpaper layer and leaves the clock/password controls untouched.
    func setAttentionDetected(_ detected: Bool, mugshot: Data?) {
        guard active else { return }
        let requested: Variant = detected ? .attention : .armed
        guard requested != currentVariant else { return }
        do {
            let screens = originals.isEmpty ? NSScreen.screens : originals.map(\.screen)
            if detected { attentionRevision += 1 }
            try apply(requested, to: screens, mugshot: mugshot)
            currentVariant = requested
            logger.info("Lock wallpaper changed to \(requested.rawValue, privacy: .public)")
        } catch {
            logger.error("Live lock wallpaper update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func restore() {
        guard active || !originals.isEmpty else { return }
        let workspace = NSWorkspace.shared
        for original in originals {
            try? workspace.setDesktopImageURL(original.imageURL, for: original.screen, options: original.options)
        }
        originals.removeAll()
        active = false
        currentVariant = .armed
        logger.info("Original desktop wallpaper restored")
    }

    private func apply(_ variant: Variant, to screens: [NSScreen], mugshot: Data?) throws {
        let workspace = NSWorkspace.shared
        for screen in screens {
            let cacheTag = variant == .attention && mugshot != nil ? String(attentionRevision % 2) : nil
            let url = try renderWallpaper(for: screen, variant: variant, mugshot: mugshot, cacheTag: cacheTag)
            try workspace.setDesktopImageURL(
                url,
                for: screen,
                options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: false,
                    .fillColor: NSColor.black,
                ]
            )
        }
    }

    private func renderWallpaper(for screen: NSScreen, variant: Variant, mugshot: Data?, cacheTag: String?) throws -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Crookcooked/Wallpapers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let pixelWidth = max(1920, Int(screen.frame.width * screen.backingScaleFactor))
        let pixelHeight = max(1080, Int(screen.frame.height * screen.backingScaleFactor))
        let suffix = cacheTag.map { "-live-\($0)" } ?? ""
        let alarmTag = audibleAlarm ? "loud" : "quiet"
        let url = directory.appendingPathComponent(
            "Crookcooked-\(variant.rawValue)-\(alarmTag)-\(showAvatar ? "avatar" : "plain")\(suffix)-\(pixelWidth)x\(pixelHeight).png"
        )

        guard let bitmap = LockScreenArtwork.render(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            variant: variant.artworkVariant,
            audibleAlarm: audibleAlarm,
            showAvatar: showAvatar,
            mugshot: mugshot
        ), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try data.write(to: url, options: .atomic)
        return url
    }
}
