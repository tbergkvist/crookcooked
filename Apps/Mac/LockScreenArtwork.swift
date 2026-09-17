import AppKit
import Foundation

/// Draws the wallpaper shown behind Apple's real lock screen.
///
/// The audience is a stranger who has just touched someone else's Mac. In the two
/// seconds before they decide what to do next it has to say three things: this is
/// watched, something is already happening, and continuing makes it worse. Vague
/// menace does not deter — specifics do, so the consequences are listed plainly.
///
/// Kept free of NSWorkspace and main-actor state so the artwork can be rendered
/// and inspected on its own, without launching the app.
enum LockScreenArtwork {
    enum Variant: String, Sendable {
        /// Armed and waiting. A warning.
        case armed
        /// Someone is looking at the Mac but has not touched it. Their photo is
        /// shown; nothing sounds.
        case watching
        /// A tamper signal fired. The warning has become a statement of fact.
        case triggered
    }

    /// Everything the words depend on.
    struct Situation: Equatable, Sendable {
        var variant: Variant
        /// The owner's setting: whether a trigger sounds the siren.
        var audibleAlarm: Bool
        /// Whether the siren is sounding now. It can be silenced from the phone.
        var alarmSounding: Bool
        var showAvatar: Bool
    }

    enum Palette {
        /// Dark ground. Red only reads as alarm when there is something for it to
        /// be louder than — washing the whole screen red makes the red mean nothing.
        static let night = NSColor(calibratedRed: 0.055, green: 0.020, blue: 0.020, alpha: 1)
        /// Triggered: hot, almost glowing.
        static let signalRed = NSColor(calibratedRed: 1.0, green: 0.165, blue: 0.125, alpha: 1)
        /// Armed: saturated pillar-box red. The old maroon read as brown at a glance.
        static let deepRed = NSColor(calibratedRed: 0.902, green: 0.098, blue: 0.075, alpha: 1)
        static let evidenceWhite = NSColor(calibratedRed: 0.980, green: 0.960, blue: 0.950, alpha: 1)
    }

    static func render(
        pixelWidth: Int,
        pixelHeight: Int,
        situation: Situation,
        mugshot: Data?
    ) -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: pixelWidth, height: pixelHeight)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.current = context

        draw(
            width: CGFloat(pixelWidth),
            height: CGFloat(pixelHeight),
            situation: situation,
            mugshot: mugshot
        )

        context.flushGraphics()
        dither(bitmap)
        return bitmap
    }

    /// One source of truth for the rail's vertical rhythm, in fractions of screen
    /// height. Sizing and drawing both read from here so they cannot disagree.
    private enum Layout {
        static let topPad: CGFloat = 0.058
        static let eyebrowBlock: CGFloat = 0.062
        static let headlineLine: CGFloat = 0.115
        static let headlineGap: CGFloat = 0.012
        static let punchLine: CGFloat = 0.040
        static let punchGap: CGFloat = 0.030
        static let ruleBlock: CGFloat = 0.046
        static let factsBlock: CGFloat = 0.034
        static let bottomPad: CGFloat = 0.040

        static func railHeight(headlineLines: Int, punchLines: Int) -> CGFloat {
            topPad + eyebrowBlock
                + headlineLine * CGFloat(headlineLines) + headlineGap
                + punchLine * CGFloat(punchLines) + punchGap + ruleBlock + factsBlock
                + bottomPad
        }
    }

    // MARK: - Composition

    private static func draw(
        width: CGFloat,
        height: CGFloat,
        situation: Situation,
        mugshot: Data?
    ) {
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let variant = situation.variant
        let copy = Copy(situation)
        let accent = variant == .triggered ? Palette.signalRed : Palette.deepRed

        Palette.night.setFill()
        bounds.fill()

        // A glow bleeding off the rail rather than a full-screen wash: the panel
        // stays the brightest thing on the display, which is the whole point.
        //
        // Two stops over an area this large band badly in 8-bit, so the falloff is
        // sampled into many stops with a smooth curve. Dithering afterwards mops up
        // whatever steps survive.
        radialGlow(
            centre: NSPoint(x: width * 0.10, y: height * 0.50),
            radius: width * 0.62,
            colour: accent,
            peak: 0.30
        )

        // Hazard border: reads as "do not proceed" before any text is read.
        let border = NSBezierPath(
            roundedRect: bounds.insetBy(dx: width * 0.035, dy: width * 0.035),
            xRadius: width * 0.014,
            yRadius: width * 0.014
        )
        border.lineWidth = max(7, width * 0.004)
        accent.setStroke()
        border.stroke()

        // macOS owns the clock (top-centre) and the password field (centre), so
        // everything here lives in a left rail that cannot collide with them.
        // Height is derived from the content rather than guessed per variant:
        // the triggered headline is a line shorter, and hard-coding the two sizes
        // is how text ended up overlapping the line above it.
        let railTop = height * 0.79
        let railHeight = height * Layout.railHeight(headlineLines: copy.headline.lineCount, punchLines: copy.punch.lineCount)
        let rail = NSRect(x: width * 0.055, y: railTop - railHeight, width: width * 0.36, height: railHeight)
        let railPath = NSBezierPath(roundedRect: rail, xRadius: width * 0.012, yRadius: width * 0.012)
        accent.setFill()
        railPath.fill()

        if variant == .armed, situation.showAvatar {
            drawHeroMark(width: width, height: height, accent: accent)
        }

        drawRailContent(rail: rail, width: width, height: height, copy: copy)

        if variant != .armed, let mugshot {
            drawMugshot(mugshot, caption: copy.mugshotCaption, canvasWidth: width, canvasHeight: height)
        }
    }

    /// The words for each situation. A stranger glances rather than reads, so
    /// each line says one plain thing: what this is, what sets it off, what
    /// already happened.
    struct Copy: Equatable {
        let eyebrow: String
        let headline: String
        let punch: String
        let facts: String
        let mugshotCaption: String

        init(_ situation: Situation) {
            let consequence = situation.audibleAlarm ? "the alarm goes off." : "the owner is alerted."
            switch situation.variant {
            case .armed:
                eyebrow = "armed"
                headline = "this mac\nis armed."
                punch = "move it, type on it, or unplug it\nand \(consequence)"
                facts = "camera on  \u{2022}  photos go to the owner"
                mugshotCaption = ""
            case .watching:
                eyebrow = "you\u{2019}re on camera"
                headline = "we see\nyou."
                punch = "looking is fine. touch, move,\nor unplug it and \(consequence)"
                facts = "camera on  \u{2022}  photos go to the owner"
                mugshotCaption = "\u{25CF}  you, right now"
            case .triggered:
                eyebrow = situation.alarmSounding ? "alarm sounding" : "owner alerted"
                headline = situation.alarmSounding ? "you\u{2019}re\ncooked." : "you\u{2019}re\ncaught."
                punch = situation.alarmSounding
                    ? "the alarm is on and your\nphoto has been taken."
                    : "your photo has been taken\nand the owner alerted."
                facts = "put it down and walk away"
                mugshotCaption = "\u{25CF}  photo taken"
            }
        }
    }

    private static func drawRailContent(rail: NSRect, width: CGFloat, height: CGFloat, copy: Copy) {
        let inset = width * 0.024
        let content = rail.insetBy(dx: inset, dy: 0)
        var cursor = rail.maxY - height * Layout.topPad

        drawLogoLockup(
            in: NSRect(x: content.minX, y: cursor - height * 0.046, width: content.width, height: height * 0.046),
            status: copy.eyebrow,
            width: width
        )
        cursor -= height * Layout.eyebrowBlock

        let headlineHeight = height * Layout.headlineLine * CGFloat(copy.headline.lineCount)
        drawLeft(
            copy.headline,
            in: NSRect(x: content.minX, y: cursor - headlineHeight, width: content.width, height: headlineHeight),
            font: .systemFont(ofSize: width * 0.056, weight: .black),
            color: Palette.evidenceWhite
        )
        cursor -= headlineHeight + height * Layout.headlineGap

        let punchHeight = height * Layout.punchLine * CGFloat(copy.punch.lineCount)
        drawLeft(
            copy.punch,
            in: NSRect(x: content.minX, y: cursor - punchHeight, width: content.width, height: punchHeight),
            font: .systemFont(ofSize: width * 0.0165, weight: .heavy),
            color: Palette.evidenceWhite.withAlphaComponent(0.94)
        )
        cursor -= punchHeight + height * Layout.punchGap

        // One scannable strip instead of a bulleted list: a thief glances, they
        // do not read. The specifics still back up the threat.
        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: content.minX, y: cursor))
        rule.line(to: NSPoint(x: content.minX + content.width * 0.46, y: cursor))
        rule.lineWidth = max(2, width * 0.0016)
        Palette.evidenceWhite.withAlphaComponent(0.42).setStroke()
        rule.stroke()
        cursor -= height * Layout.ruleBlock

        drawLeft(
            copy.facts,
            in: NSRect(x: content.minX, y: cursor - height * Layout.factsBlock, width: content.width, height: height * Layout.factsBlock),
            font: .monospacedSystemFont(ofSize: width * 0.0118, weight: .bold),
            color: Palette.evidenceWhite.withAlphaComponent(0.88)
        )
    }

    // MARK: - Hero mark

    /// The big one: the mark alone on the open field, watching the room.
    ///
    /// Sits in the clear band to the right of the rail. macOS paints its clock
    /// across the top and the password field down the centre line, and this is a
    /// wallpaper behind both, so a truly centred mark would have its face covered.
    private static func drawHeroMark(
        width: CGFloat,
        height: CGFloat,
        accent: NSColor
    ) {
        let size = height * HeroMark.size
        let rect = NSRect(
            x: width * HeroMark.centreX - size / 2,
            y: height * HeroMark.centreY - size / 2,
            width: size,
            height: size
        )

        // A soft halo lifts it off the dark ground without a hard edge.
        radialGlow(
            centre: NSPoint(x: rect.midX, y: rect.midY),
            radius: size * 1.15,
            colour: accent,
            peak: 0.34
        )

        drawBrandMark(in: rect, face: accent, pupil: Palette.evidenceWhite)
    }

    private enum HeroMark {
        /// Centred in the open field right of the rail. Nudged clear of the
        /// password pill, which macOS paints across the middle of the screen at
        /// roughly 0.43-0.58 of the width.
        static let centreX: CGFloat = 0.73
        static let centreY: CGFloat = 0.52
        static let size: CGFloat = 0.30
    }

    // MARK: - Logo

    /// Wordmark and status only. The face lives once, out on the open field —
    /// repeating it at two sizes on one screen just weakened both.
    private static func drawLogoLockup(
        in rect: NSRect,
        status: String,
        width: CGFloat
    ) {
        let textRect = NSRect(
            x: rect.minX,
            y: rect.minY - rect.height * 0.14,
            width: rect.width,
            height: rect.height
        )

        let wordmark = NSMutableAttributedString(
            string: "crookcooked",
            attributes: [
                .font: NSFont.systemFont(ofSize: width * 0.0145, weight: .black),
                .foregroundColor: Palette.evidenceWhite,
                .kern: -width * 0.00035 as NSNumber,
            ]
        )
        wordmark.append(NSAttributedString(
            string: "   \u{2022}   " + status,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: width * 0.0098, weight: .bold),
                .foregroundColor: Palette.evidenceWhite.withAlphaComponent(0.68),
            ]
        ))
        wordmark.draw(in: textRect)
    }

    /// Mirrors `.brand-mark` on the site: three round corners, one sharp at the
    /// bottom left, tilted slightly, with the eyes set high in the face.
    private static func drawBrandMark(
        in rect: NSRect,
        face: NSColor = Palette.evidenceWhite,
        pupil: NSColor = Palette.deepRed
    ) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        // Tilt about the mark's own centre to match the CSS rotate(-7deg); AppKit is y-up, so the sign flips.
        let tilt = NSAffineTransform()
        tilt.translateX(by: rect.midX, yBy: rect.midY)
        tilt.rotate(byDegrees: 7)
        tilt.translateX(by: -rect.midX, yBy: -rect.midY)
        tilt.concat()

        let round = rect.width * 0.5
        let sharp = rect.width * 0.22

        let facePath = NSBezierPath()
        facePath.move(to: NSPoint(x: rect.minX, y: rect.midY))
        facePath.appendArc(from: NSPoint(x: rect.minX, y: rect.maxY), to: NSPoint(x: rect.maxX, y: rect.maxY), radius: round)
        facePath.appendArc(from: NSPoint(x: rect.maxX, y: rect.maxY), to: NSPoint(x: rect.maxX, y: rect.minY), radius: round)
        facePath.appendArc(from: NSPoint(x: rect.maxX, y: rect.minY), to: NSPoint(x: rect.minX, y: rect.minY), radius: round)
        facePath.appendArc(from: NSPoint(x: rect.minX, y: rect.minY), to: NSPoint(x: rect.minX, y: rect.maxY), radius: sharp)
        facePath.close()

        face.setFill()
        facePath.fill()

        // Proportions taken from the site: 5px dots in a 22px mark, set at 7px
        // from the top, inset 5px from each edge.
        let eyeDiameter = rect.width * (5.0 / 22.0)
        let eyeCentreY = rect.maxY - rect.height * (9.5 / 22.0)
        let leftCentreX = rect.minX + rect.width * (7.5 / 22.0)
        let rightCentreX = rect.maxX - rect.width * (7.5 / 22.0)
        for centreX in [leftCentreX, rightCentreX] {
            let eye = NSRect(
                x: centreX - eyeDiameter / 2,
                y: eyeCentreY - eyeDiameter / 2,
                width: eyeDiameter,
                height: eyeDiameter
            )
            pupil.setFill()
            NSBezierPath(ovalIn: eye).fill()
        }
    }

    // MARK: - Gradients

    /// A soft circular glow that fades to nothing at `radius`.
    ///
    /// Drawn with CoreGraphics rather than `NSGradient.draw(in:)`, which clips its
    /// radial fill to the rectangle it is given — the gradient is still partly
    /// opaque where it meets the rect edge, so that edge shows up as a box around
    /// the glow. Drawing the circles directly has no rectangle to leave a seam.
    ///
    /// The falloff is sampled into many stops on a smoothstep curve: two stops
    /// band visibly across an area this large, and a linear ramp leaves a hard
    /// ring where it terminates.
    private static func radialGlow(
        centre: NSPoint,
        radius: CGFloat,
        colour: NSColor,
        peak: CGFloat
    ) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let base = colour.usingColorSpace(.deviceRGB)
        else { return }

        let stopCount = 48
        var colours: [CGColor] = []
        var locations: [CGFloat] = []

        for step in 0...stopCount {
            let position = CGFloat(step) / CGFloat(stopCount)
            let eased = 1 - (position * position * (3 - 2 * position))
            colours.append(base.withAlphaComponent(peak * eased).cgColor)
            locations.append(position)
        }

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colours as CFArray,
            locations: locations
        ) else { return }

        context.saveGState()
        // No drawsAfterEndLocation: nothing is painted past the fade, so there is
        // no plateau of residual colour to form an edge.
        context.drawRadialGradient(
            gradient,
            startCenter: centre, startRadius: 0,
            endCenter: centre, endRadius: radius,
            options: []
        )
        context.restoreGState()
    }

    /// Breaks up 8-bit banding by nudging each pixel by well under one level.
    ///
    /// A smooth dark gradient across a whole display crosses very few of the 256
    /// available levels, so the steps between them show up as wide flat stripes.
    /// Scattering the rounding error hides the boundary: the same technique print
    /// uses, and far cheaper than a deeper colour buffer.
    private static func dither(_ bitmap: NSBitmapImageRep) {
        guard let data = bitmap.bitmapData else { return }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let rowBytes = bitmap.bytesPerRow
        let samples = bitmap.samplesPerPixel
        guard samples >= 3 else { return }

        // Deterministic so a re-render of the same screen is byte-identical.
        var seed: UInt64 = 0x9E3779B97F4A7C15

        for y in 0..<height {
            let row = data + y * rowBytes
            for x in 0..<width {
                let pixel = row + x * samples
                for channel in 0..<3 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    // -1, 0 or 1, evenly spread.
                    let noise = Int(truncatingIfNeeded: (seed >> 33) % 3) - 1
                    let value = Int(pixel[channel]) + noise
                    pixel[channel] = UInt8(max(0, min(255, value)))
                }
            }
        }
    }

    // MARK: - Pieces

    private static func drawLeft(_ string: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = font.pointSize * 0.08
        (string as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private static func drawMugshot(_ data: Data, caption: String, canvasWidth width: CGFloat, canvasHeight height: CGFloat) {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return }

        // Right-side rail: clear of Apple's clock, password tile, and the
        // power/accessibility controls in the bottom corner.
        let panel = NSRect(x: width * 0.745, y: height * 0.31, width: width * 0.19, height: height * 0.32)
        let panelPath = NSBezierPath(roundedRect: panel, xRadius: width * 0.010, yRadius: width * 0.010)
        NSColor.black.withAlphaComponent(0.72).setFill()
        panelPath.fill()
        Palette.signalRed.setStroke()
        panelPath.lineWidth = max(6, width * 0.0025)
        panelPath.stroke()

        let pad = width * 0.008
        let photoRect = NSRect(
            x: panel.minX + pad,
            y: panel.minY + height * 0.065,
            width: panel.width - pad * 2,
            height: panel.height - height * 0.085
        )
        let destinationAspect = photoRect.width / photoRect.height
        let sourceAspect = image.size.width / image.size.height
        let sourceRect: NSRect
        if sourceAspect > destinationAspect {
            let croppedWidth = image.size.height * destinationAspect
            sourceRect = NSRect(
                x: (image.size.width - croppedWidth) / 2,
                y: 0,
                width: croppedWidth,
                height: image.size.height
            )
        } else {
            let croppedHeight = image.size.width / destinationAspect
            sourceRect = NSRect(
                x: 0,
                y: (image.size.height - croppedHeight) / 2,
                width: image.size.width,
                height: croppedHeight
            )
        }
        image.draw(
            in: photoRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        drawLeft(
            caption,
            in: NSRect(x: panel.minX + pad, y: panel.minY + height * 0.017, width: panel.width - pad * 2, height: height * 0.035),
            font: .monospacedSystemFont(ofSize: width * 0.0085, weight: .bold),
            color: Palette.signalRed
        )
    }
}

private extension String {
    var lineCount: Int { components(separatedBy: "\n").count }
}
