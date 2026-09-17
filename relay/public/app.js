// Phone client for crookcooked. The pairing secret arrives in the URL fragment
// (`#k=…`), which browsers never send to the server, so the relay that serves
// this page still only ever sees ciphertext and a hashed room ID.
import { displayCode, evidenceKey, minimumSecretLength, openEvidence, roomID } from "./pairing.js";

const storageKey = "crookcooked.secret";
const decoder = new TextDecoder();

const threatTitles = {
  keyboard_or_pointer: "Keyboard or pointer activity",
  power_disconnected: "Power adapter disconnected",
  usb_attached: "USB device attached",
  camera_movement: "Camera detected movement",
  remote_request: "Remote trigger",
  manual_test: "Test trigger",
};

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];

const state = { secret: null, key: null, socket: null, attempt: 0, reconnectTimer: null, macStatus: null, streaming: false, clipURL: null };

// ---- pairing secret -------------------------------------------------------

function readSecret() {
  const fragment = new URLSearchParams(location.hash.slice(1)).get("k");
  if (fragment && fragment.length >= minimumSecretLength) {
    try { localStorage.setItem(storageKey, fragment); } catch {}
    return fragment;
  }
  try {
    const stored = localStorage.getItem(storageKey);
    // Put the secret back in the address so "Add to Home Screen" keeps it:
    // iOS gives home-screen apps separate storage from Safari.
    if (stored) history.replaceState(null, "", `#k=${encodeURIComponent(stored)}`);
    return stored;
  } catch {
    return null;
  }
}

const open = base64 => openEvidence(base64, state.key);

// ---- relay connection -----------------------------------------------------

// Swift's `.iso8601` date strategy rejects fractional seconds on macOS 14.
const now = () => new Date().toISOString().replace(/\.\d+Z$/, "Z");

function socketURL() {
  const url = new URL(location.href);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.hash = "";
  url.search = "";
  return url.href;
}

function connect() {
  clearTimeout(state.reconnectTimer);
  state.socket?.close();
  setConnection(state.attempt ? "reconnecting…" : "connecting…", false);

  const socket = new WebSocket(socketURL());
  // The relay forwards the Mac's messages untouched, as binary frames.
  socket.binaryType = "arraybuffer";
  state.socket = socket;
  socket.onopen = () => {
    state.attempt = 0;
    setConnection("relay online", true);
    send({ type: "hello", roomID: roomID(state.secret), role: "phone", deviceID: "web" });
  };
  socket.onmessage = message => {
    const text = typeof message.data === "string" ? message.data : decoder.decode(message.data);
    let parsed;
    try { parsed = JSON.parse(text); } catch { return; }
    handle(parsed);
  };
  socket.onclose = () => {
    if (state.socket !== socket) return;
    setConnection("offline", false);
    $("[data-peer]").textContent = "Relay unreachable. Retrying…";
    setControlsEnabled(false);
    const delay = Math.min(2 ** state.attempt, 30) * 1000;
    state.attempt += 1;
    state.reconnectTimer = setTimeout(connect, delay);
  };
}

function send(message) {
  if (state.socket?.readyState === WebSocket.OPEN) state.socket.send(JSON.stringify({ ...message, sentAt: now() }));
}

const command = name => send({ type: "command", command: name });

// ---- rendering ------------------------------------------------------------

function handle(message) {
  switch (message.type) {
    case "peer_state": {
      const macOnline = message.message === "Mac connected";
      $("[data-peer]").textContent = macOnline ? "Mac connected" : "Mac is offline or not opened yet";
      setControlsEnabled(macOnline);
      if (!macOnline && !state.macStatus) $("[data-status]").textContent = "waiting for mac";
      break;
    }
    case "status":
      setMacStatus(message.status);
      break;
    case "frame":
      showFrame(open(message.frameBase64));
      break;
    case "event":
      addAlert(message.event);
      break;
    case "clip":
      showClip(open(message.clipBase64));
      break;
  }
}

function setConnection(text, online) {
  const element = $("[data-connection]");
  element.textContent = text;
  element.classList.toggle("online", online);
}

function setControlsEnabled(enabled) {
  for (const button of $$("[data-action='toggle-arm'], [data-action='toggle-stream'], [data-action='snapshot']")) {
    button.disabled = !enabled;
  }
}

function setMacStatus(status) {
  state.macStatus = status;
  const labels = { disarmed: "disarmed", arming: "arming…", armed: "armed", triggered: "alert triggered" };
  $("[data-status]").textContent = labels[status] ?? status;
  const card = $(".status");
  card.classList.toggle("armed", status === "armed");
  card.classList.toggle("triggered", status === "triggered");
  $("[data-action='toggle-arm']").textContent = status === "disarmed" ? "Arm" : "Disarm";
}

function imageURL(bytes) {
  return bytes ? URL.createObjectURL(new Blob([bytes], { type: "image/jpeg" })) : null;
}

function showFrame(bytes) {
  const url = imageURL(bytes);
  if (!url) return;
  const image = $("[data-frame]");
  if (image.src.startsWith("blob:")) URL.revokeObjectURL(image.src);
  image.src = url;
  image.hidden = false;
  $("[data-frame-empty]").hidden = true;
}

function addAlert(event) {
  if (!event) return;
  const list = $("[data-alerts]");
  if (event.id && list.querySelector(`[data-id="${CSS.escape(event.id)}"]`)) return;

  const item = document.createElement("li");
  if (event.id) item.dataset.id = event.id;
  const title = document.createElement("strong");
  title.textContent = threatTitles[event.kind] ?? "Security event";
  const time = document.createElement("time");
  const occurred = new Date(event.occurredAt);
  time.dateTime = occurred.toISOString();
  time.textContent = occurred.toLocaleString();
  item.append(title, time);

  const evidence = open(event.evidenceBase64);
  if (evidence) {
    const image = document.createElement("img");
    image.alt = "Camera evidence";
    image.src = imageURL(evidence);
    item.append(image);
    showFrame(evidence);
  }
  list.prepend(item);
  $("[data-alerts-empty]").hidden = true;

  // Replayed alerts from before this page opened should not flash as new.
  if (Date.now() - occurred.getTime() < 5 * 60 * 1000) raiseAlarm(title.textContent);
}

function showClip(bytes) {
  if (!bytes) return;
  if (state.clipURL) URL.revokeObjectURL(state.clipURL);
  state.clipURL = URL.createObjectURL(new Blob([bytes], { type: "video/quicktime" }));
  $("[data-clip-video]").src = state.clipURL;
  $("[data-clip-download]").href = state.clipURL;
  $("[data-clip]").hidden = false;
}

function raiseAlarm(title) {
  $("[data-alarm-title]").textContent = title;
  $("[data-alarm]").hidden = false;
  navigator.vibrate?.([300, 150, 300]);
}

// ---- wiring ---------------------------------------------------------------

const actions = {
  "toggle-arm": () => command(state.macStatus === "disarmed" || !state.macStatus ? "arm" : "disarm"),
  "toggle-stream": button => {
    state.streaming = !state.streaming;
    command(state.streaming ? "start_stream" : "stop_stream");
    button.textContent = state.streaming ? "Stop live view" : "Start live view";
  },
  snapshot: () => command("request_snapshot"),
  "dismiss-alarm": () => { $("[data-alarm]").hidden = true; },
  forget: () => {
    if (!confirm("Forget this Mac? You will need to scan its code again.")) return;
    try { localStorage.removeItem(storageKey); } catch {}
    location.replace(location.pathname);
  },
};

document.addEventListener("click", event => {
  const button = event.target.closest("[data-action]");
  if (button) actions[button.dataset.action]?.(button);
});

state.secret = readSecret();
if (state.secret && state.secret.length >= minimumSecretLength) {
  state.key = evidenceKey(state.secret);
  $("[data-verify]").textContent = displayCode(state.secret);
  $$("[data-paired]").forEach(element => { element.hidden = false; });
  connect();
  // iOS suspends sockets in the background; reconnect as soon as the page is back.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && state.socket?.readyState !== WebSocket.OPEN) {
      state.attempt = 0;
      connect();
    }
  });
} else {
  $("[data-unpaired]").hidden = false;
}
