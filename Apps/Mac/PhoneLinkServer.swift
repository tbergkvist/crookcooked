import CryptoKit
import Darwin
import Foundation
import Network
import CrookcookedCore

/// Serves the phone page and an encrypted event stream to phones on the same network.
///
/// There is no relay or account: the QR code is a link to this server, with the
/// pairing secret in the URL fragment. Everything after the page itself is sealed
/// with that secret — events and frames as server-sent events, commands as POSTs.
final class PhoneLinkServer {
    static let preferredPort: UInt16 = 47_823
    private static let maximumStreams = 4
    private static let maximumCommandBytes = 16 * 1024
    private static let retainedEvents = 10
    /// Connections that have not finished a request yet. Anyone on the network
    /// can open one, so there must be a ceiling.
    private static let maximumPendingConnections = 32

    /// Called on the main queue with the pairing link, or nil when the Mac has no usable network.
    var onPairingLinkChange: ((String?) -> Void)?
    /// Called on the main queue with the number of connected phones.
    var onPhoneCountChange: ((Int) -> Void)?
    var onCommand: ((RemoteCommand) -> Void)?

    private let queue = DispatchQueue(label: "app.crookcooked.phone-link")
    private let pathMonitor = NWPathMonitor()
    private let staticFiles: [String: (data: Data, contentType: String)]
    private var listener: NWListener?
    private var secret: String {
        didSet { accessTokenDigest = Self.digest(of: PairingSecret.accessToken(from: secret)) }
    }
    private var accessTokenDigest: SHA256.Digest
    private var streams: [ObjectIdentifier: EventStream] = [:]
    private var unfinishedRequests = Set<ObjectIdentifier>()
    private var replayGuard = CommandReplayGuard()
    private var status = PhoneMessage(type: .status, status: .disarmed)
    private var recentEvents: [PhoneMessage] = []
    private var latestClip: (id: String, data: Data)?
    private var heartbeat: DispatchSourceTimer?
    private var lastPairingLink: String??

    private final class EventStream {
        let connection: NWConnection
        let openedAt = Date()
        var pendingSends = 0
        init(connection: NWConnection) { self.connection = connection }
    }

    init(secret: String) {
        self.secret = secret
        accessTokenDigest = Self.digest(of: PairingSecret.accessToken(from: secret))
        staticFiles = Self.loadStaticFiles()
    }

    func start() {
        queue.async { [self] in
            startListener(port: Self.preferredPort)
            pathMonitor.pathUpdateHandler = { [weak self] _ in self?.publishPairingLink() }
            pathMonitor.start(queue: queue)

            let timer = DispatchSource.makeTimerSource(queue: queue)
            // The phone treats a silent Mac as a lost Mac, so keep talking.
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in
                guard let self, !self.streams.isEmpty else { return }
                self.status.sentAt = Date()
                self.broadcast(self.status, droppable: true)
            }
            timer.resume()
            heartbeat = timer
        }
    }

    func updateSecret(_ newSecret: String) {
        queue.async { [self] in
            guard newSecret != secret else { return }
            secret = newSecret
            // Phones holding the old secret can no longer read anything.
            streams.values.forEach { $0.connection.cancel() }
            streams.removeAll()
            publishPhoneCount()
            publishPairingLink()
        }
    }

    func sendStatus(_ value: CrookcookedStatus, detail: String?, alarmSounding: Bool) {
        queue.async { [self] in
            status = PhoneMessage(type: .status, status: value, detail: detail, alarmSounding: alarmSounding)
            broadcast(status, droppable: false)
        }
    }

    func sendEvent(_ event: CrookcookedEvent, snapshot: Data?) {
        var event = event
        event.evidenceBase64 = snapshot?.base64EncodedString()
        let message = PhoneMessage(type: .event, event: event)
        queue.async { [self] in
            recentEvents.append(message)
            if recentEvents.count > Self.retainedEvents { recentEvents.removeFirst() }
            broadcast(message, droppable: false)
        }
    }

    func sendFrame(_ jpeg: Data) {
        queue.async { [self] in
            guard !streams.isEmpty else { return }
            broadcast(PhoneMessage(type: .frame, frameBase64: jpeg.base64EncodedString()), droppable: true)
        }
    }

    func sendClip(_ movie: Data) {
        queue.async { [self] in
            let id = UUID().uuidString
            latestClip = (id, movie)
            broadcast(PhoneMessage(type: .clip, clipID: id), droppable: false)
        }
    }

    func sendNotice(_ text: String) {
        queue.async { [self] in broadcast(PhoneMessage(type: .notice, detail: text), droppable: false) }
    }

    // MARK: - Listener

    private func startListener(port: UInt16) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let endpointPort = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: parameters, on: endpointPort)
        else { return }

        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.publishPairingLink()
            case .failed:
                listener?.cancel()
                self.listener = nil
                // Something else holds the usual port; any port works, the QR code carries it.
                if port != 0 { self.startListener(port: 0) } else { self.publishPairingLink() }
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func publishPairingLink() {
        let link: String?
        if let port = listener?.port?.rawValue, let host = Self.localAddress() {
            link = PairingLink.url(host: host, port: port, secret: secret)
        } else {
            link = nil
        }
        guard lastPairingLink != .some(link) else { return }
        lastPairingLink = .some(link)
        DispatchQueue.main.async { [weak self] in self?.onPairingLinkChange?(link) }
    }

    private static func localAddress() -> String? {
        let candidates = ipv4Interfaces().map { interface in
            let octets = [24, 16, 8, 0].map { String(interface.address >> $0 & 0xFF) }
            return LocalAddressPicker.Candidate(interface: interface.name, address: octets.joined(separator: "."))
        }
        return LocalAddressPicker.pick(from: candidates)
    }

    private static func isLocalPeer(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        let peer: IPv4Address?
        switch host {
        case .ipv4(let address): peer = address
        case .ipv6(let address): peer = address.isLoopback ? IPv4Address("127.0.0.1") : address.asIPv4
        default: peer = nil
        }
        guard let peer, peer.rawValue.count == 4 else { return false }
        let value = peer.rawValue.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let subnets = ipv4Interfaces().map { LocalNetworkPolicy.Subnet(address: $0.address, mask: $0.mask) }
        return LocalNetworkPolicy.allowsPeer(value, subnets: subnets)
    }

    /// Up, running IPv4 interfaces with address and netmask in host byte order.
    private static func ipv4Interfaces() -> [(name: String, address: UInt32, mask: UInt32)] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        return sequence(first: first, next: { $0.pointee.ifa_next }).compactMap { pointer in
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, let netmask = entry.ifa_netmask,
                  address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0
            else { return nil }
            let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            return (String(cString: entry.ifa_name), value, mask)
        }
    }

    // MARK: - Requests

    private func accept(_ connection: NWConnection) {
        guard Self.isLocalPeer(connection.endpoint), unfinishedRequests.count < Self.maximumPendingConnections else {
            return connection.cancel()
        }
        let key = ObjectIdentifier(connection)
        unfinishedRequests.insert(key)
        connection.start(queue: queue)
        readRequest(on: connection, buffer: Data())
        // Drop connections that never finish sending a request.
        queue.asyncAfter(deadline: .now() + 15) { [weak self, weak connection] in
            guard let self, self.unfinishedRequests.remove(key) != nil else { return }
            connection?.cancel()
        }
    }

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            let ended = error != nil || isComplete

            switch HTTPRequestHead.parse(buffer) {
            case .invalid:
                self.unfinishedRequests.remove(ObjectIdentifier(connection))
                self.respond(on: connection, status: "400 Bad Request")
            case .incomplete where ended:
                self.unfinishedRequests.remove(ObjectIdentifier(connection))
                connection.cancel()
            case .incomplete:
                self.readRequest(on: connection, buffer: buffer)
            case .complete(let head, let bodyOffset):
                let body = buffer.dropFirst(bodyOffset)
                if head.contentLength > Self.maximumCommandBytes {
                    self.unfinishedRequests.remove(ObjectIdentifier(connection))
                    self.respond(on: connection, status: "413 Content Too Large")
                } else if body.count >= head.contentLength {
                    self.route(head, body: Data(body.prefix(head.contentLength)), on: connection)
                } else if ended {
                    self.unfinishedRequests.remove(ObjectIdentifier(connection))
                    connection.cancel()
                } else {
                    self.readRequest(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func route(_ request: HTTPRequestHead, body: Data, on connection: NWConnection) {
        unfinishedRequests.remove(ObjectIdentifier(connection))
        guard LocalNetworkPolicy.allowsHost(request.host) else {
            return respond(on: connection, status: "421 Misdirected Request")
        }
        switch (request.method, request.path) {
        case ("GET", "/events"):
            guard isAuthorized(request) else { return respond(on: connection, status: "403 Forbidden") }
            openEventStream(on: connection)
        case ("POST", "/command"):
            guard isAuthorized(request) else { return respond(on: connection, status: "403 Forbidden") }
            receiveCommand(body, on: connection)
        case ("GET", "/clip"):
            guard isAuthorized(request) else { return respond(on: connection, status: "403 Forbidden") }
            guard let clip = latestClip, clip.id == request.query["id"],
                  let sealed = try? LinkCrypto.seal(clip.data, secret: secret)
            else { return respond(on: connection, status: "404 Not Found") }
            respond(on: connection, status: "200 OK", contentType: "application/octet-stream", body: sealed)
        case ("GET", let path), ("HEAD", let path):
            guard let file = staticFiles[path] else { return respond(on: connection, status: "404 Not Found") }
            respond(on: connection, status: "200 OK", contentType: file.contentType, body: request.method == "HEAD" ? Data() : file.data)
        default:
            respond(on: connection, status: "405 Method Not Allowed")
        }
    }

    private func isAuthorized(_ request: HTTPRequestHead) -> Bool {
        // Compare digests so timing does not reveal how much of the token matched.
        Self.digest(of: request.query["t"] ?? "") == accessTokenDigest
    }

    private static func digest(of token: String) -> SHA256.Digest {
        SHA256.hash(data: Data(token.utf8))
    }

    private func receiveCommand(_ body: Data, on connection: NWConnection) {
        guard let envelope = PhoneLinkCoding.openCommand(String(decoding: body, as: UTF8.self), secret: secret) else {
            return respond(on: connection, status: "400 Bad Request")
        }
        guard replayGuard.accept(envelope) else {
            return respond(on: connection, status: "409 Conflict")
        }
        respond(on: connection, status: "204 No Content")
        DispatchQueue.main.async { [weak self] in self?.onCommand?(envelope.command) }
    }

    private func openEventStream(on connection: NWConnection) {
        if streams.count >= Self.maximumStreams, let oldest = streams.values.min(by: { $0.openedAt < $1.openedAt }) {
            oldest.connection.cancel()
        }
        let stream = EventStream(connection: connection)
        let key = ObjectIdentifier(connection)
        streams[key] = stream

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.removeStream(key)
            default: break
            }
        }
        // A phone never sends anything on this connection; a read that ends means it left.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak connection] _, _, _, _ in
            connection?.cancel()
        }

        let head = "HTTP/1.1 200 OK\r\n" + Self.headers(contentType: "text/event-stream") + "\r\nretry: 2000\n\n"
        connection.send(content: Data(head.utf8), completion: .idempotent)

        var catchUp = [status] + recentEvents
        if let clip = latestClip { catchUp.append(PhoneMessage(type: .clip, clipID: clip.id)) }
        for message in catchUp {
            if let event = Self.serverSentEvent(message, secret: secret) { write(event, to: stream, droppable: false) }
        }
        publishPhoneCount()
    }

    private func removeStream(_ key: ObjectIdentifier) {
        guard streams.removeValue(forKey: key) != nil else { return }
        publishPhoneCount()
    }

    private func publishPhoneCount() {
        let count = streams.count
        DispatchQueue.main.async { [weak self] in self?.onPhoneCountChange?(count) }
    }

    private func broadcast(_ message: PhoneMessage, droppable: Bool) {
        // Encrypted once, whatever the number of phones.
        guard !streams.isEmpty, let event = Self.serverSentEvent(message, secret: secret) else { return }
        streams.values.forEach { write(event, to: $0, droppable: droppable) }
    }

    private static func serverSentEvent(_ message: PhoneMessage, secret: String) -> Data? {
        guard let sealed = try? PhoneLinkCoding.seal(message, secret: secret) else { return nil }
        return Data("data: \(sealed)\n\n".utf8)
    }

    private func write(_ event: Data, to stream: EventStream, droppable: Bool) {
        // Live frames are skipped rather than queued behind a slow phone.
        if droppable && stream.pendingSends > 1 { return }
        stream.pendingSends += 1
        stream.connection.send(content: event, completion: .contentProcessed { [weak stream] error in
            guard let stream else { return }
            stream.pendingSends -= 1
            if error != nil { stream.connection.cancel() }
        })
    }

    private func respond(on connection: NWConnection, status: String, contentType: String? = nil, body: Data = Data()) {
        var head = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if let contentType { head += Self.headers(contentType: contentType) }
        var response = Data((head + "\r\n").utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func headers(contentType: String) -> String {
        [
            "Content-Type: \(contentType)",
            "Cache-Control: no-store",
            "Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' blob:; media-src 'self' blob:; connect-src 'self'; manifest-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
            "Referrer-Policy: no-referrer",
            "X-Content-Type-Options: nosniff",
        ].map { $0 + "\r\n" }.joined()
    }

    // MARK: - Static files

    private static func loadStaticFiles() -> [String: (data: Data, contentType: String)] {
        guard let root = webRoot() else { return [:] }
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }

        let types = [
            "html": "text/html; charset=utf-8",
            "js": "text/javascript; charset=utf-8",
            "css": "text/css; charset=utf-8",
            "png": "image/png",
            "mp4": "video/mp4",
            "webmanifest": "application/manifest+json",
        ]
        var files: [String: (data: Data, contentType: String)] = [:]
        for case let url as URL in enumerator {
            guard let type = types[url.pathExtension], let data = try? Data(contentsOf: url) else { continue }
            let path = "/" + url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1)
            files[path] = (data, type)
        }
        files["/"] = files["/index.html"]
        return files
    }

    /// The bundled copy in a built app, or the source folder when run with `swift run`.
    private static func webRoot() -> URL? {
        if let bundled = Bundle.main.url(forResource: "PhoneWeb", withExtension: nil) { return bundled }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PhoneWeb", isDirectory: true)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }
}
