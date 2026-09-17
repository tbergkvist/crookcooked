import AppKit
import Foundation
import OSLog

/// Puts crookcooked's artwork behind Apple's lock screen while armed, and puts
/// the owner's wallpaper back afterwards.
///
/// Rendering a full-resolution, dithered image takes long enough to stall the
/// interface, so it happens on a background queue. Images without a photo are
/// cached on disk and reused.
@MainActor
final class CrookcookedWallpaperService {
    typealias Situation = LockScreenArtwork.Situation

    private struct OriginalDesktop {
        let screen: NSScreen
        let imageURL: URL
        let options: [NSWorkspace.DesktopImageOptionKey: Any]
    }

    /// Bump when the artwork changes, so stale cached images are not reused.
    private nonisolated static let artworkVersion = 4
    private static let renderQueue = DispatchQueue(label: "app.crookcooked.wallpaper", qos: .userInitiated)

    private var originals: [OriginalDesktop] = []
    private var active = false
    private var situation = Situation(variant: .armed, audibleAlarm: true, alarmSounding: false, showAvatar: true)
    private var mugshot: Data?
    /// Alternates the photo image's file name; macOS does not reload a wallpaper whose URL is unchanged.
    private var mugshotRevision = 0
    /// Only the newest request may reach the screen when renders finish out of order.
    private var generation = 0
    private let logger = Logger(subsystem: "app.crookcooked.mac", category: "Wallpaper")

    func setAudibleAlarm(_ enabled: Bool) {
        update { $0.audibleAlarm = enabled }
    }

    func setShowAvatar(_ enabled: Bool) {
        update { $0.showAvatar = enabled }
    }

    func setAlarmSounding(_ sounding: Bool) {
        update { $0.alarmSounding = sounding }
    }

    /// Switches to someone-is-looking, back to armed, or to triggered.
    /// A triggered screen stays triggered until the Mac is disarmed.
    func show(_ variant: LockScreenArtwork.Variant, mugshot: Data?) {
        guard situation.variant != .triggered || variant == .triggered else { return }
        if let mugshot {
            self.mugshot = mugshot
            mugshotRevision += 1
        } else if variant == .armed {
            self.mugshot = nil
        }
        // A new photo needs a new image even when the words stay the same.
        update(force: mugshot != nil) { $0.variant = variant }
    }

    /// Renders the armed artwork ahead of time so arming does not wait for it.
    func prepare() {
        let jobs = Self.jobs(for: NSScreen.screens, situation: situation, mugshot: nil, revision: 0)
        Self.renderQueue.async { [logger] in
            Self.deleteStaleWallpapers()
            do {
                _ = try Self.render(jobs)
            } catch {
                logger.error("Wallpaper render failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func activate() async throws {
        guard !active else { return }
        let workspace = NSWorkspace.shared
        originals = NSScreen.screens.compactMap { screen in
            guard let imageURL = workspace.desktopImageURL(for: screen) else { return nil }
            return OriginalDesktop(screen: screen, imageURL: imageURL, options: workspace.desktopImageOptions(for: screen) ?? [:])
        }
        situation.variant = .armed
        situation.alarmSounding = false
        mugshot = nil
        active = true
        do {
            try await apply()
        } catch {
            restore()
            throw error
        }
    }

    func restore() {
        guard active || !originals.isEmpty else { return }
        generation += 1
        let workspace = NSWorkspace.shared
        for original in originals {
            try? workspace.setDesktopImageURL(original.imageURL, for: original.screen, options: original.options)
        }
        originals.removeAll()
        active = false
        situation.variant = .armed
        situation.alarmSounding = false
        mugshot = nil
        Self.renderQueue.async { Self.deletePhotoWallpapers() }
    }

    /// Photos of whoever was in front of the Mac should not outlive the armed session
    /// as wallpaper files; the evidence copy is what the owner keeps.
    private nonisolated static func deletePhotoWallpapers() {
        deleteWallpapers { $0.contains("-photo") }
    }

    /// Images from earlier artwork versions are never shown again.
    private nonisolated static func deleteStaleWallpapers() {
        deleteWallpapers { !$0.hasPrefix("v\(artworkVersion)-") }
    }

    private nonisolated static func deleteWallpapers(where matches: (String) -> Bool) {
        let files = (try? FileManager.default.contentsOfDirectory(at: wallpaperDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "png" && matches(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private nonisolated static var wallpaperDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("crookcooked/Wallpapers", isDirectory: true)
    }

    private func update(force: Bool = false, _ change: (inout Situation) -> Void) {
        var next = situation
        change(&next)
        guard next != situation || force else { return }
        situation = next
        guard active else { return }
        Task {
            do {
                try await apply()
            } catch {
                logger.error("Lock wallpaper update failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func apply() async throws {
        generation += 1
        let requested = generation
        let screens = originals.isEmpty ? NSScreen.screens : originals.map(\.screen)
        let photo = situation.variant == .armed ? nil : mugshot
        let jobs = Self.jobs(for: screens, situation: situation, mugshot: photo, revision: mugshotRevision)

        let urls = try await withCheckedThrowingContinuation { continuation in
            Self.renderQueue.async { continuation.resume(with: Result { try Self.render(jobs) }) }
        }
        guard requested == generation, active else { return }

        for (screen, url) in zip(screens, urls) {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: false,
                .fillColor: NSColor.black,
            ])
        }
    }

    // MARK: - Rendering (background)

    private struct Job: Sendable {
        let pixelWidth: Int
        let pixelHeight: Int
        let situation: Situation
        let mugshot: Data?
        let url: URL
    }

    private static func jobs(for screens: [NSScreen], situation: Situation, mugshot: Data?, revision: Int) -> [Job] {
        let directory = wallpaperDirectory
        return screens.map { screen in
            let width = max(1920, Int(screen.frame.width * screen.backingScaleFactor))
            let height = max(1080, Int(screen.frame.height * screen.backingScaleFactor))
            let name = [
                "v\(artworkVersion)",
                situation.variant.rawValue,
                situation.audibleAlarm ? "loud" : "quiet",
                situation.alarmSounding ? "sounding" : "silent",
                situation.showAvatar ? "avatar" : "plain",
                mugshot == nil ? "nophoto" : "photo\(revision % 2)",
                "\(width)x\(height)",
            ].joined(separator: "-")
            return Job(pixelWidth: width, pixelHeight: height, situation: situation, mugshot: mugshot,
                       url: directory.appendingPathComponent(name + ".png"))
        }
    }

    private nonisolated static func render(_ jobs: [Job]) throws -> [URL] {
        try jobs.map { job in
            // Photo-free artwork never changes for the same situation and size.
            if job.mugshot == nil, FileManager.default.fileExists(atPath: job.url.path) { return job.url }

            try FileManager.default.createDirectory(at: job.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let bitmap = LockScreenArtwork.render(
                pixelWidth: job.pixelWidth,
                pixelHeight: job.pixelHeight,
                situation: job.situation,
                mugshot: job.mugshot
            ), let data = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: job.url, options: .atomic)
            return job.url
        }
    }
}
