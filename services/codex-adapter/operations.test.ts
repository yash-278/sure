import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { Operations } from "./operations.ts";
const request = (id, priority = "background") => ({
  id,
  prompt: "synthetic",
  schema: { type: "object" },
  priority,
});
const tick = () => new Promise((resolve) => setTimeout(resolve, 5));
function setup(t) {
  const dir = mkdtempSync(join(tmpdir(), "sure-ops-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return new Operations({}, dir);
}
test("same operation is generated once and cached across restart", async (t) => {
  const ops = setup(t);
  let calls = 0;
  ops.generate = async () => {
    calls++;
    return { output: { ok: true } };
  };
  ops.submit(request("a"));
  await tick();
  ops.submit(request("a"));
  assert.equal(calls, 1);
  const restored = new Operations({}, ops.directory);
  assert.equal(restored.get("a").status, "completed");
});
test("rejects conflicting reuse of an operation ID", async (t) => {
  const ops = setup(t);
  ops.pause(true);
  ops.submit(request("a"));
  assert.throws(
    () => ops.submit({ ...request("a"), prompt: "changed" }),
    /operation_conflict/,
  );
});
test("restarted queued operations are interrupted rather than repeated", (t) => {
  const ops = setup(t);
  ops.pause(true);
  ops.submit(request("a"));
  const restored = new Operations({}, ops.directory);
  assert.equal(restored.get("a").status, "interrupted");
});
test("paused background work yields to interactive work", async (t) => {
  const ops = setup(t);
  const calls = [];
  ops.generate = async (r) => {
    calls.push(r.id);
    return { output: {} };
  };
  ops.pause(true);
  ops.submit(request("background"));
  ops.submit(request("chat", "interactive"));
  await tick();
  assert.deepEqual(calls, ["chat"]);
  ops.pause(false);
  await tick();
  assert.deepEqual(calls, ["chat", "background"]);
});
test("cancelled queued jobs never run", async (t) => {
  const ops = setup(t);
  ops.pause(true);
  ops.generate = async () => {
    assert.fail("cancelled job ran");
  };
  ops.submit(request("a"));
  await ops.cancel("a");
  ops.pause(false);
  await tick();
  assert.equal(ops.get("a").status, "cancelled");
});
test("generation requires subscription authentication", async (t) => {
  const ops = setup(t);
  ops.rpc = { call: async () => ({ account: { type: "apiKey" } }) };
  await assert.rejects(ops.generate(request("a")), /not_connected/);
});
test("exhausted subscription does not start a generation", async (t) => {
  const ops = setup(t);
  const calls = [];
  ops.rpc = {
    call: async (method) => {
      calls.push(method);
      return method === "account/read"
        ? { account: { type: "chatgpt" } }
        : { ordinaryUsageAllowed: false };
    },
  };
  await assert.rejects(ops.generate(request("a")), /quota_exhausted/);
  assert.deepEqual(calls, ["account/read", "account/rateLimits/read"]);
});
test("quota wait resumes the same operation after reset", async (t) => {
  const ops = setup(t);
  let calls = 0;
  ops.generate = async () => {
    calls++;
    if (calls === 1) {
      ops.quotaUntil = Date.now() + 60000;
      throw new Error("quota_exhausted");
    }
    return { output: { ok: true } };
  };
  ops.submit(request("quota"));
  await tick();
  assert.equal(ops.get("quota").status, "waiting_quota");
  clearTimeout(ops.quotaTimer);
  ops.quotaUntil = 0;
  await ops.drain();
  assert.equal(ops.get("quota").status, "completed");
  assert.equal(calls, 2);
});
test("quota-waiting operations can be cancelled", async (t) => {
  const ops = setup(t);
  ops.generate = async () => {
    ops.quotaUntil = Date.now() + 60000;
    throw new Error("quota_exhausted");
  };
  ops.submit(request("quota"));
  await tick();
  await ops.cancel("quota");
  clearTimeout(ops.quotaTimer);
  assert.equal(ops.get("quota").status, "cancelled");
  assert.equal(ops.queue.length, 0);
});

test("cancelling before turn acknowledgement interrupts before the next generation", async (t) => {
  const ops = setup(t);
  const { EventEmitter } = await import("node:events");
  const rpc = new EventEmitter();
  let acknowledge = null;
  let interrupted = false;
  rpc.call = async (method) => {
    if (method === "account/read") return { account: { type: "chatgpt" } };
    if (method === "account/rateLimits/read") return {};
    if (method === "model/list")
      return { data: [{ id: "test", isDefault: true }] };
    if (method === "thread/start") return { thread: { id: "thread" } };
    if (method === "turn/start")
      return new Promise((resolve) => {
        acknowledge = resolve;
      });
    if (method === "turn/interrupt") {
      interrupted = true;
      return {};
    }
  };
  ops.rpc = rpc;
  ops.submit(request("active"));
  await tick();
  const cancelled = ops.cancel("active");
  assert.equal(ops.running, true);
  acknowledge({ turn: { id: "turn" } });
  await cancelled;
  await tick();
  assert.equal(interrupted, true);
  assert.equal(ops.get("active").status, "cancelled");
  assert.equal(ops.running, false);
});

test("generation timeout interrupts active work", async (t) => {
  const ops = setup(t);
  ops.timeoutMs = 5;
  const { EventEmitter } = await import("node:events");
  const rpc = new EventEmitter();
  let interrupted = false;
  rpc.call = async (method) => {
    if (method === "account/read") return { account: { type: "chatgpt" } };
    if (method === "account/rateLimits/read") return {};
    if (method === "model/list")
      return { data: [{ id: "test", isDefault: true }] };
    if (method === "thread/start") return { thread: { id: "thread" } };
    if (method === "turn/start") return { turn: { id: "turn" } };
    if (method === "turn/interrupt") {
      interrupted = true;
      return {};
    }
  };
  ops.rpc = rpc;
  ops.submit(request("timeout"));
  await new Promise((resolve) => setTimeout(resolve, 30));
  assert.equal(interrupted, true);
  assert.equal(ops.get("timeout").error, "generation_timeout");
});
