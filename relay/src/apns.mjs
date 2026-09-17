import crypto from "node:crypto";
import fs from "node:fs";
import http2 from "node:http2";

const base64url = value => Buffer.from(value).toString("base64url");

export class APNsClient {
  constructor(environment = process.env) {
    this.teamID = environment.APNS_TEAM_ID;
    this.keyID = environment.APNS_KEY_ID;
    this.topic = environment.APNS_TOPIC;
    this.host = environment.APNS_PRODUCTION === "true" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
    this.privateKey = environment.APNS_KEY_PATH ? fs.readFileSync(environment.APNS_KEY_PATH, "utf8") : null;
    this.cachedToken = null;
    this.tokenCreatedAt = 0;
  }

  get enabled() {
    return Boolean(this.teamID && this.keyID && this.topic && this.privateKey);
  }

  async alert(tokens, kind) {
    if (!this.enabled) return;
    await Promise.allSettled(tokens.map(token => this.send(token, {
      aps: {
        alert: { title: "Crookcooked alert", body: readableKind(kind) },
        "interruption-level": "time-sensitive",
      },
    })));
  }

  send(deviceToken, payload) {
    const client = http2.connect(`https://${this.host}`);
    return new Promise((resolve, reject) => {
      client.once("error", reject);
      const request = client.request({
        ":method": "POST",
        ":path": `/3/device/${deviceToken}`,
        authorization: `bearer ${this.providerToken()}`,
        "apns-topic": this.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
      });
      let status = 0;
      request.on("response", headers => { status = headers[":status"]; });
      request.on("end", () => {
        client.close();
        status === 200 ? resolve() : reject(new Error(`APNs returned ${status}`));
      });
      request.on("error", error => { client.close(); reject(error); });
      request.end(JSON.stringify(payload));
    });
  }

  providerToken() {
    const now = Math.floor(Date.now() / 1000);
    if (this.cachedToken && now - this.tokenCreatedAt < 50 * 60) return this.cachedToken;
    const header = base64url(JSON.stringify({ alg: "ES256", kid: this.keyID }));
    const claims = base64url(JSON.stringify({ iss: this.teamID, iat: now }));
    const unsigned = `${header}.${claims}`;
    const signature = crypto.sign("sha256", Buffer.from(unsigned), { key: this.privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url");
    this.cachedToken = `${unsigned}.${signature}`;
    this.tokenCreatedAt = now;
    return this.cachedToken;
  }
}

function readableKind(kind) {
  return String(kind).replaceAll("_", " ").replace(/^./, value => value.toUpperCase());
}

