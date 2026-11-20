// A local webhook receiver for Focus Mode's functional test: verifies X-ZenMode-Signature
// (sha256=HMAC of the raw body with the secret) and prints each event.
//   node scripts/webhook-receiver.mjs <secret> [port=8787]
import {createServer} from "node:http";
import {createHmac, timingSafeEqual} from "node:crypto";

const [secret, port = "8787"] = process.argv.slice(2);
if (!secret) { console.error("usage: node scripts/webhook-receiver.mjs <secret> [port]"); process.exit(2); }
createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const body = Buffer.concat(chunks);
    const want = "sha256=" + createHmac("sha256", secret).update(body).digest("hex");
    const got = String(req.headers["x-zenmode-signature"] ?? "");
    const ok = got.length === want.length && timingSafeEqual(Buffer.from(got), Buffer.from(want));
    console.log(`${new Date().toISOString()} ${ok ? "VERIFIED" : "BAD SIGNATURE"} ${body.toString()}`);
    res.writeHead(ok ? 200 : 401).end();
  });
}).listen(Number(port), "127.0.0.1", () => console.log(`listening on http://127.0.0.1:${port}/hook`));
