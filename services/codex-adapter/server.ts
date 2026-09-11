import { spawn } from "node:child_process";
import { timingSafeEqual } from "node:crypto";
import { mkdirSync } from "node:fs";
import { createServer } from "node:http";
import { LazyRpc } from "./lifecycle.ts";
import { Operations } from "./operations.ts";
import { CodexRpc } from "./rpc.ts";

const token = process.env.ADAPTER_TOKEN;
if (!token || token.length < 32)
  throw new Error("ADAPTER_TOKEN must be configured");
const codexHome = process.env.CODEX_HOME || "/data/codex";
mkdirSync(codexHome, { recursive: true, mode: 0o700 });
let login = null;
let loginTimer = null;
const rpc = new LazyRpc(
  () =>
    new CodexRpc(
      spawn("codex", ["app-server"], {
        env: {
          PATH: process.env.PATH,
          HOME: "/home/node",
          CODEX_HOME: codexHome,
        },
        stdio: ["pipe", "pipe", "pipe"],
      }),
    ),
  () =>
    operations.running ||
    operations.queue.length > 0 ||
    login?.state === "pending" ||
    login?.state === "starting",
);
rpc.on("account/login/completed", (event) => {
  if (login?.loginId === event.loginId) {
    clearTimeout(loginTimer);
    login = {
      loginId: event.loginId,
      state: event.success ? "connected" : "failed",
    };
  }
});
const operations = new Operations(
  rpc,
  process.env.OPERATIONS_DIR || "/data/operations",
);

function authorised(header) {
  const supplied = Buffer.from(header || "");
  const expected = Buffer.from(`Bearer ${token}`);
  return (
    supplied.length === expected.length && timingSafeEqual(supplied, expected)
  );
}

const server = createServer(async (req, res) => {
  res.setHeader("Content-Type", "application/json");
  res.setHeader("Cache-Control", "no-store");
  const reply = (status, body) => {
    res.writeHead(status);
    res.end(JSON.stringify(body));
  };
  if (req.method === "GET" && req.url === "/health")
    return reply(200, { ready: true });
  if (!authorised(req.headers.authorization))
    return reply(401, { error: "unauthorized" });
  try {
    if (req.method === "GET" && req.url === "/account") {
      const result = await rpc.call("account/read", { refreshToken: true });
      // Never return tokens even if upstream adds fields in a later release.
      return reply(200, {
        account: result.account
          ? {
              type: result.account.type,
              email: result.account.email,
              planType: result.account.planType,
            }
          : null,
      });
    }
    if (req.method === "GET" && req.url === "/models") {
      const data = [];
      let cursor = null;
      do {
        const page = await rpc.call("model/list", {
          includeHidden: false,
          cursor,
        });
        data.push(...page.data);
        if (page.nextCursor && page.nextCursor === cursor)
          throw new Error("invalid_cursor");
        cursor = page.nextCursor;
      } while (cursor);
      return reply(200, { data });
    }
    if (req.method === "GET" && req.url === "/limits") {
      const limits = await rpc.call("account/rateLimits/read");
      return reply(200, {
        ordinaryUsageAllowed: limits.ordinaryUsageAllowed,
        rateLimits: limits.rateLimits,
        rateLimitsByLimitId: limits.rateLimitsByLimitId,
      });
    }
    if (req.method === "GET" && req.url === "/settings")
      return reply(200, { paused: operations.paused });
    if (req.method === "POST" && req.url === "/settings") {
      const body = await readBody(req);
      if (typeof body.paused !== "boolean")
        return reply(422, { error: "invalid_request" });
      operations.pause(body.paused);
      return reply(200, { paused: operations.paused });
    }
    if (req.method === "DELETE" && req.url === "/operations") {
      operations.pause(true);
      for (const request of [...operations.queue])
        await operations.cancel(request.id);
      if (operations.currentRequest)
        await operations.cancel(operations.currentRequest);
      return reply(200, { status: "cancelled" });
    }
    if (req.method === "POST" && req.url === "/operations") {
      const operation = operations.submit(await readBody(req));
      // A paused queue is still in-memory work. Keep Codex present just as for
      // an active queue, even when this is the first request after idle sleep.
      if (operations.queue.length > 0) await rpc.ensure();
      return reply(202, operation);
    }
    const operationPath = req.url?.match(
      /^\/operations\/([a-zA-Z0-9_-]{1,128})$/,
    );
    if (operationPath && req.method === "GET") {
      const operation = operations.get(operationPath[1]);
      return reply(operation ? 200 : 404, operation || { error: "not_found" });
    }
    if (operationPath && req.method === "DELETE") {
      await operations.cancel(operationPath[1]);
      return reply(200, { status: "cancelled" });
    }
    if (req.method === "GET" && req.url === "/login") {
      if (login?.state === "pending" && Date.now() > login.expiresAt) {
        await rpc.call("account/login/cancel", { loginId: login.loginId });
        login = { state: "expired" };
      }
      return reply(200, login || { state: "idle" });
    }
    if (req.method === "POST" && req.url === "/login") {
      if (login?.state === "pending" || login?.state === "starting")
        return reply(200, login);
      login = { state: "starting" };
      let result = null;
      try {
        result = await rpc.call("account/login/start", {
          type: "chatgptDeviceCode",
        });
      } catch (error) {
        login = { state: "failed" };
        throw error;
      }
      login = {
        state: "pending",
        loginId: result.loginId,
        expiresAt: Date.now() + 10 * 60 * 1000,
        verificationUrl: result.verificationUrl,
        userCode: result.userCode,
      };
      clearTimeout(loginTimer);
      loginTimer = setTimeout(
        async () => {
          if (login?.state !== "pending") return;
          const loginId = login.loginId;
          try {
            await rpc.call("account/login/cancel", { loginId });
          } catch {
            /* The expiry must release the login even if Codex failed. */
          } finally {
            if (login?.loginId === loginId) login = { state: "expired" };
          }
        },
        10 * 60 * 1000,
      );
      loginTimer.unref();
      return reply(200, login);
    }
    if (req.method === "DELETE" && req.url === "/login") {
      if (login?.loginId)
        await rpc.call("account/login/cancel", { loginId: login.loginId });
      clearTimeout(loginTimer);
      login = null;
      return reply(200, { state: "cancelled" });
    }
    if (req.method === "DELETE" && req.url === "/account") {
      await operations.disconnect();
      clearTimeout(loginTimer);
      login = null;
      return reply(200, { state: "disconnected" });
    }
    reply(404, { error: "not_found" });
  } catch (error) {
    if (
      error.message === "not_connected" &&
      req.method === "GET" &&
      req.url === "/account"
    )
      return reply(200, { account: null, reauthenticationRequired: true });
    reply(503, {
      error: ["not_connected", "quota_exhausted"].includes(error.message)
        ? error.message
        : "codex_request_failed",
    });
  }
});
server.listen(Number(process.env.PORT || 3000), "::");
rpc.on("unavailable", () => server.close(() => process.exit(1)));
process.on("SIGTERM", () => {
  clearTimeout(loginTimer);
  void rpc.close();
  server.close();
});

async function readBody(req) {
  let body = "";
  for await (const chunk of req) {
    body += chunk;
    if (Buffer.byteLength(body) > 15 * 1024 * 1024)
      throw new Error("request_too_large");
  }
  return JSON.parse(body);
}
