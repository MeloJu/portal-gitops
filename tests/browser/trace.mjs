// Abre o app num Chromium real, faz login e navega: as chamadas saem pelo fetch instrumentado do app.
import { chromium } from "playwright";

const base = "http://l2.localhost";
const email = `browser-${Date.now()}@l2.dev`;
const password = "SenhaForte#2026";

// Chromium resolve *.localhost sempre para o próprio loopback; aponta l2.localhost para o host.
const browser = await chromium.launch({ args: [`--host-resolver-rules=MAP l2.localhost ${process.env.HOSTIP}`] });
const page = await browser.newPage({ userAgent: "Mozilla/5.0 (X11; Linux x86_64) Chrome/131.0 Safari/537.36" });
const otlp = [];
page.on("request", (r) => { if (r.url().includes("/otlp/")) otlp.push(r.method() + " " + new URL(r.url()).pathname); });
const otlpResp = [];
page.on("response", (r) => { if (r.url().includes("/otlp/")) otlpResp.push(r.status()); });
page.on("requestfailed", (r) => { if (r.url().includes("/otlp/")) otlpResp.push("FALHOU " + (r.failure()?.errorText || "")); });
const api = [];
page.on("request", (r) => {
  if (r.url().includes("/api/")) api.push({ path: new URL(r.url()).pathname, tp: r.headers()["traceparent"] || null });
});

await page.goto(base + "/", { waitUntil: "domcontentloaded", timeout: 30000 });
// Mesmo fetch que o app usa (window.fetch já foi instrumentado pelo startTelemetry no main.tsx).
const reg = await page.evaluate(async ([e, p]) => {
  const r = await fetch("/api/auth/register", { method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ name: "Browser", email: e, password: p }), credentials: "same-origin" });
  return r.status;
}, [email, password]);
// Uma pessoa não troca de página em milissegundos: 2 s bastam para o lote de spans (enviado a cada 1 s) sair.
await page.waitForTimeout(2000);
await page.goto(base + "/dashboard", { waitUntil: "domcontentloaded", timeout: 30000 });
await page.waitForTimeout(4000); // o frontend exporta os spans a cada 1 s

console.log(JSON.stringify({ register: reg, apiCalls: api.slice(0, 6), otlpExports: otlp, otlpResp }));
await browser.close();
