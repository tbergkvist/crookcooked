import SwiftUI
import CrookcookedCore

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var showPermissions = false
    @State private var showPairingDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                controlPanel
                pairingPanel

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        protectionPanel
                        activityPanel
                    }
                    VStack(spacing: 18) {
                        protectionPanel
                        activityPanel
                    }
                }

                permissionsPanel
                limitations
            }
            .frame(maxWidth: 1180)
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(CrookTheme.canvas.ignoresSafeArea())
        .foregroundStyle(CrookTheme.ink)
    }

    private var header: some View {
        HStack(spacing: 13) {
            brandMark

            VStack(alignment: .leading, spacing: 1) {
                Text("crookcooked")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(-1.1)
                Text("step away. it screams. you get the photo.")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(CrookTheme.muted)
            }

            Spacer()

            Label("local detection", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(CrookTheme.muted)
        }
        .padding(.horizontal, 4)
    }

    private var brandMark: some View {
        ZStack {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 14, bottomLeading: 5, bottomTrailing: 14, topTrailing: 14),
                style: .continuous
            )
            .fill(CrookTheme.red)

            HStack(spacing: 4) {
                Circle().fill(.white).frame(width: 5, height: 5)
                Circle().fill(.white).frame(width: 5, height: 5)
            }
        }
        .frame(width: 31, height: 31)
        .rotationEffect(.degrees(-6))
        .accessibilityHidden(true)
    }

    private var controlPanel: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 15) {
                statusPill

                Text(model.statusLabel.lowercased())
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .tracking(-2.2)
                    .foregroundStyle(.white)

                Text(statusExplanation)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    model.configuration.audibleAlarm ? "alarm will sound" : "quiet mode — silent alert only",
                    systemImage: model.configuration.audibleAlarm ? "speaker.wave.3.fill" : "speaker.slash.fill"
                )
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(model.configuration.audibleAlarm ? CrookTheme.red : .white.opacity(0.55))
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 11) {
                Button(action: performPrimaryAction) {
                    HStack(spacing: 10) {
                        Text(primaryActionTitle)
                        Image(systemName: primaryActionIcon)
                    }
                    .font(.system(size: 15, weight: .bold))
                    .frame(minWidth: 150)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .buttonStyle(CrookActionButtonStyle(isDestructive: model.status != .disarmed))

                Text(primaryActionHint)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(CrookTheme.night)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(statusAccent.opacity(0.18))
                        .frame(width: 240, height: 240)
                        .blur(radius: 45)
                        .offset(x: 70, y: -100)
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusAccent)
                .frame(width: 8, height: 8)
                .shadow(color: statusAccent.opacity(0.7), radius: 6)
            Text(statusShortLabel)
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private var protectionPanel: some View {
        panel {
            panelHeader("protection", subtitle: "what watches the mac", icon: "scope")

            HStack(spacing: 8) {
                alwaysOnChip("input", icon: "keyboard")
                alwaysOnChip("power", icon: "powerplug.fill")
                alwaysOnChip("usb", icon: "externaldrive.fill")
            }

            Divider().overlay(CrookTheme.line)

            VStack(spacing: 3) {
                settingRow(
                    "camera movement",
                    detail: "Detect sustained scene changes",
                    icon: "camera.metering.matrix",
                    isOn: $model.configuration.cameraMovementDetection
                )
                settingRow(
                    "attention warning",
                    detail: "React when someone faces the Mac",
                    icon: "eye.fill",
                    isOn: $model.configuration.faceAttentionWarning
                )
                settingRow(
                    "evidence clip",
                    detail: "Record 12 seconds after a trigger",
                    icon: "record.circle",
                    isOn: $model.configuration.recordEvidence
                )
                settingRow(
                    "lock screen avatar",
                    detail: "The mark watches and blinks while armed",
                    icon: "eye.circle.fill",
                    isOn: $model.configuration.lockScreenAvatar
                )
            }

            Divider().overlay(CrookTheme.line)

            HStack(alignment: .top, spacing: 13) {
                Image(systemName: model.configuration.audibleAlarm ? "speaker.wave.3.fill" : "speaker.slash.fill")
                    .frame(width: 28, height: 28)
                    .foregroundStyle(CrookTheme.red)
                    .background(CrookTheme.red.opacity(0.11), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("audible alarm")
                        .font(.system(size: 13, weight: .bold))
                    Text(model.configuration.audibleAlarm
                         ? "On. Sounds only after a confirmed trigger."
                         : "Quiet mode. Evidence still records and your iPhone is still alerted.")
                        .font(.system(size: 11))
                        .foregroundStyle(CrookTheme.muted)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { model.configuration.audibleAlarm },
                    set: { model.setAudibleAlarm($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(CrookTheme.red)
            }
            .padding(13)
            .background(CrookTheme.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    /// Pairing sits directly under the arm button: a Mac that is not paired sends
    /// its evidence nowhere, so this is the first thing to finish after install.
    private var pairingPanel: some View {
        panel {
            HStack(alignment: .center, spacing: 11) {
                panelHeader(
                    model.isPhonePaired ? "iphone paired" : "pair your iphone",
                    subtitle: model.isPhonePaired ? "encrypted evidence relay" : "scan once — takes a few seconds",
                    icon: model.isPhonePaired ? "checkmark.shield.fill" : "qrcode"
                )

                Spacer()

                if model.isPhonePaired {
                    Button(showPairingDetail ? "hide code" : "show code") {
                        showPairingDetail.toggle()
                    }
                    .buttonStyle(CrookSecondaryButtonStyle())
                }
            }

            if !model.isPhonePaired || showPairingDetail {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 22) {
                        pairingQR
                        pairingInstructions
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        pairingQR
                        pairingInstructions
                    }
                }
            } else {
                Label("Evidence will reach your iPhone.", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CrookTheme.muted)
            }
        }
    }

    private var pairingQR: some View {
        VStack(spacing: 9) {
            if model.pairingPayload.isReachableFromPhone {
                QRCodeView(payload: model.pairingPayload.encoded, size: 178)
            } else {
                // A loopback relay would give the phone a link it can never open.
                Label("Set a relay address your iPhone can reach to show the code.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CrookTheme.red)
                    .multilineTextAlignment(.center)
                    .frame(width: 178, height: 178)
            }

            Text("scan with your iphone camera")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(CrookTheme.muted)
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CrookTheme.line, lineWidth: 1)
        }
    }

    private var pairingInstructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                pairingStep(1, "Open the Camera app on your iPhone.")
                pairingStep(2, "Point it at this code and tap the link.")
                pairingStep(3, "Check both screens show the same number.")
            }

            HStack(alignment: .firstTextBaseline, spacing: 11) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("verify on both devices")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrookTheme.muted)
                    Text(model.pairingCode)
                        .font(.system(size: 27, weight: .black, design: .monospaced))
                        .tracking(3)
                }

                Spacer()

                Label(model.relayState.lowercased(), systemImage: "circle.fill")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(relayTone)
            }

            Divider().overlay(CrookTheme.line)

            VStack(alignment: .leading, spacing: 6) {
                Text("relay address")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrookTheme.muted)
                TextField("wss://relay.example.com", text: $model.configuration.relayURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(CrookTheme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CrookTheme.line, lineWidth: 1)
                    }
            }

            HStack(spacing: 9) {
                Button("copy pairing link") { model.copyPairingLink() }
                    .buttonStyle(CrookSecondaryButtonStyle())
                Button("regenerate", role: .destructive) { model.regeneratePairingSecret() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CrookTheme.red)
                Spacer()
            }
        }
        .frame(minWidth: 250)
    }

    private func pairingStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(CrookTheme.red, in: Circle())
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Permissions are setup detail, not a daily concern, so they stay folded away
    /// behind one button that reports the real state on demand.
    private var permissionsPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 27, height: 27)
                    .foregroundStyle(.white)
                    .background(CrookTheme.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("permissions")
                        .font(.system(size: 13, weight: .bold))
                    Text(model.hasCheckedPermissions ? permissionSummary : "checked automatically when you arm")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(CrookTheme.muted)
                }

                Spacer()

                Button("test permissions") {
                    model.testPermissions()
                    withAnimation(.easeOut(duration: 0.16)) { showPermissions = true }
                }
                .buttonStyle(CrookSecondaryButtonStyle())

                Button {
                    withAnimation(.easeOut(duration: 0.16)) { showPermissions.toggle() }
                } label: {
                    Image(systemName: showPermissions ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CrookTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showPermissions ? "Hide permission detail" : "Show permission detail")
            }

            if showPermissions {
                VStack(spacing: 7) {
                    permissionRow(.camera, detail: model.cameraState, tone: cameraTone)
                    permissionRow(.inputMonitoring, detail: model.inputMonitoringState, tone: inputTone)
                    permissionRow(.accessibility, detail: model.securityState, tone: securityTone)
                }

                Text("crookcooked only reports armed after macOS confirms Apple\u{2019}s real lock screen.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CrookTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CrookTheme.line, lineWidth: 1)
        }
    }

    private var permissionSummary: String {
        let blocked = [cameraTone, inputTone, securityTone].filter { $0 == CrookTheme.red }.count
        return blocked == 0 ? "all clear" : "\(blocked) needs attention"
    }

    private func permissionRow(_ target: PermissionTarget, detail: String, tone: Color) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: target.icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 27, height: 27)
                .foregroundStyle(tone)
                .background(tone.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                    .font(.system(size: 11, weight: .bold))
                Text(model.hasCheckedPermissions ? detail : target.why)
                    .font(.system(size: 9))
                    .foregroundStyle(CrookTheme.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if tone == CrookTheme.red {
                Button("open settings") { model.openSettings(for: target) }
                    .buttonStyle(CrookSecondaryButtonStyle())
            } else {
                Circle()
                    .fill(tone)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(11)
        .background(CrookTheme.canvas.opacity(0.75), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var activityPanel: some View {
        panel {
            panelHeader("activity", subtitle: "latest signal events", icon: "waveform.path.ecg")

            if model.events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(CrookTheme.muted)
                    Text("nothing shady yet")
                        .font(.system(size: 14, weight: .bold))
                    Text("Signals will appear here while the Mac is armed.")
                        .font(.system(size: 11))
                        .foregroundStyle(CrookTheme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.events.prefix(6)) { event in
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: event.kind))
                                .frame(width: 30, height: 30)
                                .foregroundStyle(CrookTheme.red)
                                .background(CrookTheme.red.opacity(0.09), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.kind.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(event.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(CrookTheme.muted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(event.occurredAt, style: .time)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(CrookTheme.muted)
                        }
                        .padding(.vertical, 9)

                        if event.id != model.events.prefix(6).last?.id {
                            Divider().overlay(CrookTheme.line)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var limitations: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .foregroundStyle(CrookTheme.red)
            Text("MacBooks expose no supported accelerometer API. Movement uses camera scene change plus input, USB, and power signals. Authentication stays inside Apple’s lock screen; crookcooked refuses to arm unless macOS confirms it.")
                .font(.system(size: 10))
                .foregroundStyle(CrookTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(22)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(CrookTheme.line, lineWidth: 1)
            }
    }

    private func panelHeader(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 31, height: 31)
                .foregroundStyle(.white)
                .background(CrookTheme.red, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(CrookTheme.muted)
            }
        }
    }

    private func alwaysOnChip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(CrookTheme.canvas, in: Capsule())
            .overlay { Capsule().stroke(CrookTheme.line, lineWidth: 1) }
    }

    private func settingRow(_ title: String, detail: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(CrookTheme.red)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(CrookTheme.muted)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(CrookTheme.red)
        }
        .padding(.vertical, 7)
    }

    private func readinessItem(_ title: String, detail: String, icon: String, tone: Color) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 29, height: 29)
                .foregroundStyle(tone)
                .background(tone.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(CrookTheme.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Circle()
                .fill(tone)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
        }
        .padding(11)
        .background(CrookTheme.canvas.opacity(0.75), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var statusAccent: Color {
        switch model.status {
        case .disarmed: return .white.opacity(0.55)
        case .arming: return CrookTheme.red
        case .armed: return CrookTheme.acid
        case .triggered: return CrookTheme.red
        }
    }

    private var statusShortLabel: String {
        switch model.status {
        case .disarmed: return "not armed"
        case .arming: return "locking now"
        case .armed: return "protection active"
        case .triggered: return "tamper detected"
        }
    }

    private var statusExplanation: String {
        switch model.status {
        case .disarmed:
            return "Arm before stepping away. crookcooked will invoke Apple’s lock screen, verify it, then watch the Mac."
        case .arming:
            return "Preparing sensors and locking through macOS. You can cancel before the countdown ends."
        case .armed:
            return "The Mac is locked and its enabled signals are watching for interference."
        case .triggered:
            return "A confirmed signal fired. Evidence and status are being sent to the paired iPhone when available."
        }
    }

    private var primaryActionTitle: String {
        switch model.status {
        case .disarmed: return "arm & lock"
        case .arming: return "cancel arming"
        case .armed, .triggered: return "disarm"
        }
    }

    private var primaryActionIcon: String {
        switch model.status {
        case .disarmed: return "lock.fill"
        case .arming: return "xmark"
        case .armed, .triggered: return "lock.open.fill"
        }
    }

    private var primaryActionHint: String {
        switch model.status {
        case .disarmed: return "locks in \(model.configuration.armingDelaySeconds)s"
        case .arming: return "\(model.countdown)s remaining"
        case .armed: return "unlocking macOS also disarms"
        case .triggered: return "stop the active response"
        }
    }

    private func performPrimaryAction() {
        model.status == .disarmed ? model.arm() : model.disarm()
    }

    private var securityTone: Color {
        tone(for: model.securityState, positive: ["ready", "verified", "active"], negative: ["failed", "could not", "unavailable"])
    }

    private var cameraTone: Color {
        tone(for: model.cameraState, positive: ["ready", "active"], negative: ["denied", "no frames"])
    }

    private var inputTone: Color {
        tone(for: model.inputMonitoringState, positive: ["ready"], negative: ["required", "denied"])
    }

    private var relayTone: Color {
        tone(for: model.relayState, positive: ["connected", "paired"], negative: ["offline", "error", "invalid", "enter"])
    }

    private func tone(for value: String, positive: [String], negative: [String]) -> Color {
        let normalized = value.lowercased()
        if negative.contains(where: normalized.contains) { return CrookTheme.red }
        if positive.contains(where: normalized.contains) { return CrookTheme.acidDark }
        return CrookTheme.muted
    }

    private func icon(for kind: ThreatKind) -> String {
        switch kind {
        case .keyboardOrPointer: return "keyboard"
        case .powerDisconnected: return "powerplug.fill"
        case .usbAttached: return "externaldrive.connected.to.line.below.fill"
        case .cameraMovement: return "camera.metering.matrix"
        case .remoteRequest: return "iphone.radiowaves.left.and.right"
        case .manualTest: return "testtube.2"
        }
    }
}

private enum CrookTheme {
    static let canvas = Color(red: 0.961, green: 0.933, blue: 0.918)
    static let ink = Color(red: 0.075, green: 0.043, blue: 0.039)
    static let night = Color(red: 0.063, green: 0.031, blue: 0.027)
    static let muted = Color(red: 0.427, green: 0.380, blue: 0.365)
    static let line = Color(red: 0.239, green: 0.078, blue: 0.067).opacity(0.16)
    static let red = Color(red: 0.949, green: 0.243, blue: 0.196)
    static let acid = Color(red: 0.792, green: 1.0, blue: 0.392)
    static let acidDark = Color(red: 0.254, green: 0.475, blue: 0.039)
}

private struct CrookActionButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isDestructive ? Color.white : CrookTheme.ink)
            .background(
                isDestructive ? CrookTheme.red : Color.white,
                in: Capsule()
            )
            .overlay { Capsule().stroke(.white.opacity(isDestructive ? 0 : 0.25), lineWidth: 1) }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CrookSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(CrookTheme.ink)
            .background(CrookTheme.canvas, in: Capsule())
            .overlay { Capsule().stroke(CrookTheme.line, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

/// Regenerates only when the payload actually changes; QR rasterisation is not
/// something to redo on every SwiftUI body evaluation.
private struct QRCodeView: View {
    let payload: String
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "qrcode")
                            .font(.system(size: size * 0.3, weight: .light))
                            .foregroundStyle(.black.opacity(0.25))
                    }
            }
        }
        .task(id: payload) {
            image = QRCodeImage.make(from: payload, size: size * 2)
        }
        .accessibilityLabel("Pairing QR code")
    }
}
