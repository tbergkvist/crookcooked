# iPhone connection

The iPhone needs no app. The Mac runs a small web server while crookcooked is open, and the QR code is a link to it:

```
http://192.168.1.20:47823/#k=SECRET
```

1. The Camera app opens the link in Safari. The page, its scripts, and its crypto libraries come from the Mac (`Apps/PhoneWeb` in this repository).
2. The part after `#` is never sent over the network by the browser, so the pairing secret stays on the phone. The page stores it so the link keeps working, including from **Add to Home Screen**.
3. The page derives a key from the secret and opens an event stream (`/events`). Status, alerts, evidence photos, and live frames arrive sealed with ChaCha20-Poly1305. Evidence clips are fetched sealed from `/clip`.
4. Arm, disarm, silence alarm, live view, and snapshot are sent as sealed commands to `/command`. The Mac refuses commands it cannot open, commands older than two minutes, and any command it has already seen.

Both screens show the same six-digit verify code. **New code** on the Mac replaces the secret and disconnects every phone.

## Watch mode

iPhone pauses web pages when the screen locks, and a web page on the local network cannot receive push notifications. So that alerts are not missed, **Start watching** keeps the screen on, and the phone sounds its own alarm when:

- the Mac reports a tamper event, or
- the Mac goes silent for 20 seconds while armed. A closed lid, sleep, or a lost network all look like this.

If the page was paused, it reconnects when you return, and shows the latest alerts, photos, and clip it missed.

## Alarm and silencing

If the Mac is touched, moved, or unplugged and quiet mode is off, the siren plays through the Mac's built-in speakers at full volume. Volume keys, mute, and plugging in headphones are undone within a quarter of a second. **Silence Mac alarm** on the phone stops the siren but keeps the Mac triggered and sending evidence; **Disarm** ends it. The owner's volume and output device are restored afterwards.

Someone only looking at the Mac does not trigger anything: the lock screen shows them their photo, and the phone gets a notice with the same photo.

## When the page won't load

- The iPhone must be on the same network as the Mac, and the Mac must be awake with crookcooked open.
- Some café, hotel, and office Wi-Fi keeps devices from seeing each other. Turn on **Personal Hotspot** on the iPhone, join it from the Mac, and scan the new code; the address changes with the network.
- If the macOS firewall asks whether crookcooked may accept incoming connections, allow it.

## Remote arming

Arming from the phone works only when the Mac can lock itself without a key press: through the macOS login service, or with Accessibility enabled for crookcooked. Otherwise the phone shows why and the Mac stays disarmed. If arming fails for any other reason, the phone is told that too.

## Security notes

- Nothing leaves the local network, and no third party is involved.
- The server only answers devices on one of the Mac's own subnets. On networks that give the Mac a public address, the rest of the internet is refused before anything is read.
- Requests must name the Mac by IP address, so a website the phone visits cannot reach the server through DNS rebinding.
- Someone else on the same Wi-Fi sees only ciphertext, the Mac's address, and traffic timing. The stream and clip endpoints also require a token derived one-way from the secret.
- The page itself is plain HTTP. An attacker who can actively intercept traffic on that network while the page loads could replace it and learn the secret. On untrusted Wi-Fi, prefer Personal Hotspot.
