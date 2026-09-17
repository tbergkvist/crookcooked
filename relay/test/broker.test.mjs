import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";
import { RoomBroker } from "../src/broker.mjs";

class FakeSocket extends EventEmitter {
  readyState = 1;
  sent = [];
  closed = null;
  send(value) { this.sent.push(JSON.parse(value.toString())); }
  close(code, reason) { this.closed = { code, reason }; this.emit("close"); }
  message(value) { this.emit("message", Buffer.from(JSON.stringify(value))); }
}

const roomID = "a".repeat(64);
const hello = role => ({ type: "hello", roomID, role, deviceID: role, sentAt: new Date().toISOString() });

test("routes phone commands to the Mac and Mac frames to the phone", () => {
  const broker = new RoomBroker();
  const mac = new FakeSocket();
  const phone = new FakeSocket();
  broker.attach(mac);
  broker.attach(phone);
  mac.message(hello("mac"));
  phone.message(hello("phone"));

  phone.message({ type: "command", command: "arm", sentAt: new Date().toISOString() });
  assert.equal(mac.sent.at(-1).command, "arm");

  mac.message({ type: "frame", frameBase64: "encrypted", sentAt: new Date().toISOString() });
  assert.equal(phone.sent.at(-1).frameBase64, "encrypted");
});

test("replays retained alerts to a phone that reconnects", () => {
  const broker = new RoomBroker();
  const mac = new FakeSocket();
  broker.attach(mac);
  mac.message(hello("mac"));
  mac.message({ type: "event", event: { id: "1" }, sentAt: new Date().toISOString() });

  const phone = new FakeSocket();
  broker.attach(phone);
  phone.message(hello("phone"));
  assert.equal(phone.sent.some(message => message.type === "event"), true);
});

test("deletes retained room data after the retention window", async () => {
  const broker = new RoomBroker({ retentionMilliseconds: 5 });
  const mac = new FakeSocket();
  broker.attach(mac);
  mac.message(hello("mac"));
  mac.message({ type: "event", event: { id: "1" }, sentAt: new Date().toISOString() });
  mac.close(1000, "done");

  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(broker.rooms.has(roomID), false);
});

test("rejects clients that do not begin with a valid hello", () => {
  const broker = new RoomBroker();
  const socket = new FakeSocket();
  broker.attach(socket);
  socket.message({ type: "command", command: "disarm" });
  assert.equal(socket.closed.code, 1008);
});

test("requests a push for registered phones when an event arrives", () => {
  const alerts = [];
  const broker = new RoomBroker({ onAlert: (tokens, kind) => alerts.push({ tokens, kind }) });
  const mac = new FakeSocket();
  const phone = new FakeSocket();
  broker.attach(mac);
  broker.attach(phone);
  mac.message(hello("mac"));
  phone.message({ ...hello("phone"), pushToken: "ab".repeat(32) });
  mac.message({ type: "event", event: { kind: "usb_attached" }, sentAt: new Date().toISOString() });
  assert.deepEqual(alerts, [{ tokens: ["ab".repeat(32)], kind: "usb_attached" }]);
});
