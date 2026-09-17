const allowedMacMessages = new Set(["status", "event", "frame", "clip"]);
const allowedPhoneMessages = new Set(["command", "register_push"]);

// Swift clients decode dates with `.iso8601`, which rejects fractional seconds
// on macOS 14.
export const timestamp = () => new Date().toISOString().replace(/\.\d+Z$/, "Z");

export class RoomBroker {
  constructor({ maxHistoryBytes = 32 * 1024 * 1024, maxMessagesPerSecond = 12, retentionMilliseconds = 60 * 60 * 1000, onAlert = () => {} } = {}) {
    this.rooms = new Map();
    this.clients = new Map();
    this.maxHistoryBytes = maxHistoryBytes;
    this.maxMessagesPerSecond = maxMessagesPerSecond;
    this.retentionMilliseconds = retentionMilliseconds;
    this.onAlert = onAlert;
  }

  attach(socket) {
    this.pruneExpiredRooms();
    this.clients.set(socket, { roomID: null, role: null, pushToken: null, windowStarted: Date.now(), messageCount: 0 });
    socket.on("message", raw => this.receive(socket, raw));
    socket.on("close", () => this.leave(socket));
  }

  receive(socket, raw) {
    const client = this.clients.get(socket);
    if (!client) return;
    if (!this.allowMessage(client)) return socket.close(1008, "rate limit");

    let message;
    try {
      message = JSON.parse(raw.toString());
    } catch {
      return this.send(socket, { type: "error", message: "invalid JSON", sentAt: timestamp() });
    }

    if (!client.roomID) return this.join(socket, client, message);
    if (message.type === "hello" || message.roomID) return socket.close(1008, "invalid session message");

    const allowed = client.role === "mac" ? allowedMacMessages : allowedPhoneMessages;
    if (!allowed.has(message.type)) return;

    const room = this.rooms.get(client.roomID);
    if (!room) return;
    if (client.role === "phone" && message.type === "register_push") {
      if (/^[a-f0-9]{32,256}$/.test(message.pushToken ?? "")) {
        client.pushToken = message.pushToken;
        room.pushTokens.add(message.pushToken);
      }
      return;
    }
    const destinations = client.role === "mac" ? room.phones : room.macs;
    for (const peer of destinations) this.sendRaw(peer, raw);

    if (client.role === "mac" && ["status", "event", "clip"].includes(message.type)) {
      this.remember(room, raw, message.type);
    }
    if (client.role === "mac" && message.type === "event") {
      const tokens = [...room.pushTokens];
      if (tokens.length) this.onAlert(tokens, message.event?.kind ?? "Security event");
    }
  }

  join(socket, client, message) {
    if (message.type !== "hello" || !/^[a-f0-9]{64}$/.test(message.roomID ?? "") || !["mac", "phone"].includes(message.role)) {
      return socket.close(1008, "hello required");
    }
    client.roomID = message.roomID;
    client.role = message.role;
    client.pushToken = /^[a-f0-9]{32,256}$/.test(message.pushToken ?? "") ? message.pushToken : null;
    const room = this.rooms.get(client.roomID) ?? { macs: new Set(), phones: new Set(), pushTokens: new Set(), history: [], historyBytes: 0, expiresAt: null, expiryTimer: null };
    this.rooms.set(client.roomID, room);
    room.pushTokens ??= new Set();
    if (room.expiryTimer) clearTimeout(room.expiryTimer);
    room.expiryTimer = null;
    if (client.pushToken) room.pushTokens.add(client.pushToken);
    room.expiresAt = null;
    (client.role === "mac" ? room.macs : room.phones).add(socket);

    if (client.role === "phone") {
      for (const item of room.history) this.sendRaw(socket, item.raw);
    }
    this.broadcastPeerState(room);
  }

  leave(socket) {
    const client = this.clients.get(socket);
    this.clients.delete(socket);
    if (!client?.roomID) return;
    const room = this.rooms.get(client.roomID);
    if (!room) return;
    room.macs.delete(socket);
    room.phones.delete(socket);
    this.broadcastPeerState(room);
    if (room.macs.size === 0 && room.phones.size === 0) {
      if (room.history.length) this.scheduleExpiry(client.roomID, room);
      else this.deleteRoom(client.roomID, room);
    }
  }

  scheduleExpiry(roomID, room) {
    if (room.expiryTimer) clearTimeout(room.expiryTimer);
    room.expiresAt = Date.now() + this.retentionMilliseconds;
    room.expiryTimer = setTimeout(() => this.deleteRoom(roomID, room), this.retentionMilliseconds);
    room.expiryTimer.unref?.();
  }

  deleteRoom(roomID, room) {
    if (this.rooms.get(roomID) !== room) return;
    if (room.expiryTimer) clearTimeout(room.expiryTimer);
    this.rooms.delete(roomID);
  }

  remember(room, raw, type) {
    const buffer = Buffer.isBuffer(raw) ? raw : Buffer.from(raw);
    // Status is replaced; alerts and the latest encrypted clip are retained until
    // the room disappears. The relay cannot decrypt any camera bytes.
    if (type === "status" || type === "clip") {
      room.history = room.history.filter(item => {
        if (item.type !== type) return true;
        room.historyBytes -= item.bytes;
        return false;
      });
    }
    room.history.push({ raw: buffer, bytes: buffer.length, type });
    room.historyBytes += buffer.length;
    while (room.historyBytes > this.maxHistoryBytes && room.history.length) {
      const removed = room.history.shift();
      room.historyBytes -= removed.bytes;
    }
  }

  broadcastPeerState(room) {
    const now = timestamp();
    for (const mac of room.macs) this.send(mac, { type: "peer_state", message: room.phones.size ? "iPhone connected" : "Connected; waiting for iPhone", sentAt: now });
    for (const phone of room.phones) this.send(phone, { type: "peer_state", message: room.macs.size ? "Mac connected" : "Connected; Mac is offline", sentAt: now });
  }

  allowMessage(client) {
    const now = Date.now();
    if (now - client.windowStarted >= 1000) {
      client.windowStarted = now;
      client.messageCount = 0;
    }
    client.messageCount += 1;
    return client.messageCount <= this.maxMessagesPerSecond;
  }

  pruneExpiredRooms() {
    const now = Date.now();
    for (const [roomID, room] of this.rooms) {
      if (room.expiresAt && room.expiresAt <= now) this.deleteRoom(roomID, room);
    }
  }

  send(socket, value) {
    this.sendRaw(socket, JSON.stringify(value));
  }

  sendRaw(socket, value) {
    if (socket.readyState === 1) socket.send(value);
  }
}
