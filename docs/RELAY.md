# Relay

The relay requires Node.js 20.6 or newer.

```sh
cd relay
npm ci
HOST=127.0.0.1 npm start
```

The relay also serves the phone web page. The Mac app turns its relay address into the QR code: `ws://host:8787` becomes `http://host:8787/#k=SECRET`, and `wss://` becomes `https://`. The secret stays in the URL fragment, which browsers never send to the server.

A phone cannot reach `127.0.0.1`, so the Mac app hides the QR code until the relay address is reachable from elsewhere. For LAN access, bind `HOST=0.0.0.0` only on a trusted network and enter `ws://<relay-lan-ip>:8787` in the Mac app. For internet access, put the relay behind a TLS reverse proxy and enter its `wss://` address in the Mac app. `GET /health` is the health check.

Docker users can run `docker compose up --build`. The compose configuration exposes port 8787 to the LAN.

Optional APNs alerts use `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_TOPIC`, `APNS_KEY_PATH`, and `APNS_PRODUCTION=true|false`. Keep the `.p8` file outside the repository. APNs only reaches the source-built native iPhone app, not the web page. Without it, foreground alerts and retained encrypted evidence still work when the phone reconnects.
