import Foundation
import CrookcookedCore

final class RelayClient: NSObject, URLSessionWebSocketDelegate {
    var onStateChange: ((String) -> Void)?
    var onCommand: ((RemoteCommand) -> Void)?

    private let role: RelayRole
    private var session: URLSession!
    private var socket: URLSessionWebSocketTask?
    private var endpointURL: URL?
    private var secret = ""
    private let deviceID: String
    private var reconnectAttempt = 0
    private var reconnectWork: DispatchWorkItem?

    init(role: RelayRole) {
        self.role = role
        self.deviceID = Host.current().localizedName ?? UUID().uuidString
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect(url: URL, secret: String) {
        guard ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            onStateChange?("Invalid relay URL")
            return
        }
        reconnectWork?.cancel()
        reconnectWork = nil
        socket?.cancel(with: .goingAway, reason: nil)
        endpointURL = url
        self.secret = secret
        reconnectAttempt = 0
        openConnection()
    }

    func send(_ message: RelayMessage) {
        guard let data = try? RelayCoding.encoder.encode(message),
              let text = String(data: data, encoding: .utf8)
        else { return }
        socket?.send(.string(text)) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.onStateChange?("Relay error: \(error.localizedDescription)")
            }
        }
    }

    func sendFrame(_ data: Data) {
        guard let encrypted = try? EvidenceCrypto.seal(data, secret: secret) else { return }
        send(RelayMessage(type: .frame, frameBase64: encrypted.base64EncodedString()))
    }

    func sendClip(_ data: Data) {
        guard let encrypted = try? EvidenceCrypto.seal(data, secret: secret) else { return }
        send(RelayMessage(type: .clip, clipBase64: encrypted.base64EncodedString()))
    }

    func sendEvent(_ event: CrookcookedEvent, snapshot: Data?) {
        var event = event
        if let snapshot, let encrypted = try? EvidenceCrypto.seal(snapshot, secret: secret) {
            event.evidenceBase64 = encrypted.base64EncodedString()
        }
        send(RelayMessage(type: .event, event: event))
    }

    private func openConnection() {
        guard let endpointURL else { return }
        let task = session.webSocketTask(with: endpointURL)
        socket = task
        onStateChange?(reconnectAttempt == 0 ? "Connecting…" : "Reconnecting…")
        task.resume()
        receive(from: task)
    }

    private func receive(from task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            DispatchQueue.main.async {
                guard let self, let task, self.socket === task else { return }
                switch result {
                case .failure(let error):
                    self.onStateChange?("Offline: \(error.localizedDescription)")
                    self.scheduleReconnect()
                case .success(let payload):
                    let data: Data?
                    switch payload {
                    case .string(let text): data = text.data(using: .utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: data = nil
                    }
                    if let data, let message = try? RelayCoding.decoder.decode(RelayMessage.self, from: data) {
                        if message.type == .command, let command = message.command { self.onCommand?(command) }
                        if message.type == .peerState, let value = message.message { self.onStateChange?(value) }
                    }
                    self.receive(from: task)
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard endpointURL != nil, reconnectWork == nil else { return }
        socket = nil
        let delay = min(pow(2, Double(reconnectAttempt)), 30)
        reconnectAttempt += 1
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWork = nil
            self.openConnection()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { [weak self, weak webSocketTask] in
            guard let self, let webSocketTask, self.socket === webSocketTask else { return }
            self.reconnectAttempt = 0
            self.reconnectWork?.cancel()
            self.reconnectWork = nil
            self.onStateChange?("Connected; waiting for iPhone")
            self.send(.hello(secret: self.secret, role: self.role, deviceID: self.deviceID))
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { [weak self, weak webSocketTask] in
            guard let self, let webSocketTask, self.socket === webSocketTask else { return }
            self.onStateChange?("Offline")
            self.scheduleReconnect()
        }
    }
}
