// Phone page for crookcooked, served by the Mac on the local network.
//
// The pairing secret arrives in the URL fragment (`#k=…`), which the browser never
// sends over the network. Messages from the Mac arrive as sealed server-sent events;
// commands go back as sealed POSTs.
import { accessToken, displayCode, linkKey, minimumSecretLength, open, openMessage, sealCommand } from "./pairing.js";

const storageKey = "crookcooked.secret";
/// The Mac sends a heartbeat every five seconds.
const silenceBeforeAlarmMs = 20_000;
/// Alerts replayed from before this page opened are shown, but do not ring.
const freshAlertMs = 2 * 60_000;

const threatTitles = {
  keyboard_or_pointer: "Keyboard or pointer activity",
  power_disconnected: "Power adapter disconnected",
  usb_attached: "USB device attached",
  camera_movement: "Mac was moved",
  remote_request: "Remote trigger",
  manual_test: "Test trigger",
};
const statusTitles = { disarmed: "disarmed", arming: "arming…", armed: "armed", triggered: "alert!" };

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];

const state = {
  key: null,
  token: null,
  events: null,
  lastMessageAt: 0,
  macStatus: null,
  streaming: false,
  watching: false,
  lostContact: false,
  clipID: null,
  clipURL: null,
  audio: null,
  siren: null,
  noticeTimer: null,
};

// ---- pairing --------------------------------------------------------------

function readSecret() {
  const fromLink = new URLSearchParams(location.hash.slice(1)).get("k");
  if (fromLink) {
    try { localStorage.setItem(storageKey, fromLink); } catch {}
    return fromLink;
  }
  try {
    const stored = localStorage.getItem(storageKey);
    // Keep the secret in the address so "Add to Home Screen" carries it:
    // iOS gives home-screen web apps storage separate from Safari.
    if (stored) history.replaceState(null, "", `#k=${encodeURIComponent(stored)}`);
    return stored;
  } catch {
    return null;
  }
}

// ---- connection -----------------------------------------------------------

function connect() {
  state.events?.close();
  const events = new EventSource(`events?t=${state.token}`);
  state.events = events;

  events.onopen = () => {
    state.lastMessageAt = Date.now();
    setConnection("connected", true);
    $("[data-unreachable]").hidden = true;
    setControlsEnabled(true);
  };
  events.onmessage = message => {
    const decoded = openMessage(message.data, state.key);
    if (!decoded) return;
    state.lastMessageAt = Date.now();
    // Contact is back, but the alarm stays up until the owner has seen it.
    state.lostContact = false;
    handle(decoded);
  };
  events.onerror = () => {
    setConnection("can't reach mac", false);
    setControlsEnabled(false);
    $("[data-unreachable]").hidden = false;
    // EventSource retries by itself unless the Mac refused us outright (for
    // example after "new code" on the Mac); then retry slowly.
    if (events.readyState === EventSource.CLOSED) setTimeout(() => state.events === events && connect(), 5000);
  };
}

async function command(name) {
  try {
    const response = await fetch(`command?t=${state.token}`, { method: "POST", body: sealCommand(name, state.key) });
    if (!response.ok) showNotice("Your Mac refused that command. Scan the code on the Mac again.");
  } catch {
    showNotice("Couldn't reach your Mac.");
  }
}

function watchForSilence() {
  const armed = state.macStatus === "armed" || state.macStatus === "triggered";
  const silent = Date.now() - state.lastMessageAt > silenceBeforeAlarmMs;
  if (state.watching && armed && silent && !state.lostContact) {
    state.lostContact = true;
    raiseAlarm("Lost contact with your Mac while armed");
  }
}

// ---- messages -------------------------------------------------------------

function handle(message) {
  switch (message.type) {
    case "status": return setMacStatus(message);
    case "frame": return showFrame(message.frameBase64);
    case "event": return addAlert(message.event);
    case "clip": return loadClip(message.clipID);
    case "notice": return showNotice(message.detail);
  }
}

function setMacStatus({ status, detail, alarmSounding }) {
  state.macStatus = status;
  // Silencing keeps the Mac triggered, so it gets its own button above Disarm.
  $("[data-action='silence']").hidden = !alarmSounding;
  $("[data-action='toggle-arm']").classList.toggle("secondary", Boolean(alarmSounding));
  $("[data-status]").textContent = statusTitles[status] ?? status;
  $("[data-detail]").textContent = detail || {
    disarmed: "Connected. Arm here or on the Mac.",
    arming: "Locking the Mac…",
    armed: "Every signal is being watched.",
    triggered: alarmSounding ? "Something touched your Mac. The alarm is sounding." : "Something touched your Mac.",
  }[status] || "";
  const card = $(".status");
  card.classList.toggle("armed", status === "armed");
  card.classList.toggle("triggered", status === "triggered");
  $("[data-action='toggle-arm']").textContent = status === "disarmed" ? "Arm" : "Disarm";
}

function jpegURL(base64) {
  if (!base64) return null;
  const bytes = Uint8Array.from(atob(base64), character => character.charCodeAt(0));
  return URL.createObjectURL(new Blob([bytes], { type: "image/jpeg" }));
}

function showFrame(base64) {
  const url = jpegURL(base64);
  if (!url) return;
  const image = $("[data-frame]");
  if (image.src.startsWith("blob:")) URL.revokeObjectURL(image.src);
  image.src = url;
  image.hidden = false;
  $("[data-frame-empty]").hidden = true;
}

function addAlert(event) {
  const list = $("[data-alerts]");
  if (!event || list.querySelector(`[data-id="${CSS.escape(event.id)}"]`)) return;

  const item = document.createElement("li");
  item.dataset.id = event.id;
  const title = document.createElement("strong");
  title.textContent = threatTitles[event.kind] ?? "Security event";
  const time = document.createElement("time");
  const occurred = new Date(event.occurredAt);
  time.dateTime = occurred.toISOString();
  time.textContent = occurred.toLocaleString();
  item.append(title, time);

  if (event.evidenceBase64) {
    const image = document.createElement("img");
    image.alt = "Camera evidence";
    image.src = jpegURL(event.evidenceBase64);
    item.append(image);
    showFrame(event.evidenceBase64);
  }
  list.prepend(item);
  $("[data-alerts-empty]").hidden = true;

  if (Date.now() - occurred.getTime() < freshAlertMs) raiseAlarm(title.textContent);
}

async function loadClip(id) {
  if (!id || id === state.clipID) return;
  state.clipID = id;
  try {
    const response = await fetch(`clip?t=${state.token}&id=${encodeURIComponent(id)}`);
    const movie = response.ok ? open(new Uint8Array(await response.arrayBuffer()), state.key) : null;
    if (!movie) return;
    if (state.clipURL) URL.revokeObjectURL(state.clipURL);
    state.clipURL = URL.createObjectURL(new Blob([movie], { type: "video/quicktime" }));
    $("[data-clip-video]").src = state.clipURL;
    $("[data-clip-download]").href = state.clipURL;
    $("[data-clip]").hidden = false;
  } catch {
    state.clipID = null;
  }
}

// ---- interface ------------------------------------------------------------

function setConnection(text, online) {
  const element = $("[data-connection]");
  element.textContent = text;
  element.classList.toggle("online", online);
}

function setControlsEnabled(enabled) {
  $$("[data-action='toggle-arm'], [data-action='silence'], [data-action='toggle-stream'], [data-action='snapshot']").forEach(button => {
    button.disabled = !enabled;
  });
}

function showNotice(text) {
  if (!text) return;
  const notice = $("[data-notice]");
  notice.textContent = text;
  notice.hidden = false;
  clearTimeout(state.noticeTimer);
  state.noticeTimer = setTimeout(() => { notice.hidden = true; }, 6000);
}

function raiseAlarm(title) {
  $("[data-alarm-title]").textContent = title;
  $("[data-alarm]").hidden = false;
  if (state.watching) startSiren();
}

function stopAlarm() {
  $("[data-alarm]").hidden = true;
  state.siren?.stop();
  state.siren = null;
}

/// Audio only plays after a tap, so the context is created by "Start watching".
function startSiren() {
  if (!state.audio || state.siren) return;
  const context = state.audio;
  const oscillator = context.createOscillator();
  const sweep = context.createOscillator();
  const depth = context.createGain();
  const volume = context.createGain();
  oscillator.type = "square";
  oscillator.frequency.value = 900;
  sweep.frequency.value = 2.5;
  depth.gain.value = 350;
  volume.gain.value = 0.35;
  sweep.connect(depth).connect(oscillator.frequency);
  oscillator.connect(volume).connect(context.destination);
  oscillator.start();
  sweep.start();
  state.siren = { stop: () => { oscillator.stop(); sweep.stop(); } };
}

async function setWatching(watching) {
  state.watching = watching;
  const video = $("[data-keep-awake]");
  if (watching) {
    // Play through the ring/silent switch where Safari supports it.
    if (navigator.audioSession) navigator.audioSession.type = "playback";
    state.audio ??= new AudioContext();
    await state.audio.resume().catch(() => {});
    await video.play().catch(() => {});
    state.lastMessageAt = Math.max(state.lastMessageAt, Date.now());
  } else {
    video.pause();
    stopAlarm();
  }
  $("[data-watch-state]").textContent = watching ? "On — keep this page open" : "Off";
  $("[data-action='toggle-watch']").textContent = watching ? "Stop" : "Start watching";
  $(".watch").classList.toggle("active", watching);
}

const actions = {
  "toggle-arm": () => command(state.macStatus === "disarmed" || !state.macStatus ? "arm" : "disarm"),
  "toggle-stream": button => {
    state.streaming = !state.streaming;
    command(state.streaming ? "start_stream" : "stop_stream");
    button.classList.toggle("on", state.streaming);
  },
  snapshot: () => command("request_snapshot"),
  silence: () => command("silence_alarm"),
  "toggle-watch": () => setWatching(!state.watching),
  "dismiss-alarm": stopAlarm,
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

// ---- start ----------------------------------------------------------------

const secret = readSecret();
if (secret && secret.length >= minimumSecretLength) {
  state.key = linkKey(secret);
  state.token = accessToken(secret);
  $("[data-verify]").textContent = displayCode(secret);
  $$("[data-paired]").forEach(element => { element.hidden = false; });
  connect();
  setInterval(watchForSilence, 2000);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "visible") return;
    // The page was paused, so silence while hidden says nothing about the Mac.
    state.lastMessageAt = Date.now();
    if (state.events?.readyState === EventSource.CLOSED) connect();
    if (state.watching) $("[data-keep-awake]").play().catch(() => {});
  });
} else {
  $("[data-unpaired]").hidden = false;
  setConnection("not paired", false);
}
