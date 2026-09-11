import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";
import { setTimeout as delay } from "node:timers/promises";
import { LazyRpc } from "./lifecycle.ts";

function fixture(busy = () => false) {
  const instances = [];
  const manager = new LazyRpc(
    () => {
      const child = new EventEmitter();
      child.kill = () => {
        queueMicrotask(() => child.emit("exit"));
      };
      const rpc = Object.assign(new EventEmitter(), {
        child,
        initialize: async () => {
          await delay(5);
        },
        call: async (method) => method,
      });
      child.on("exit", () => rpc.emit("unavailable"));
      instances.push(rpc);
      return rpc;
    },
    busy,
    15,
  );
  return { manager, instances };
}

test("starts lazily, shares concurrent startup, and restarts after idle exit", async () => {
  const { manager, instances } = fixture();
  assert.equal(instances.length, 0);
  assert.deepEqual(
    await Promise.all([
      manager.call("account/read"),
      manager.call("model/list"),
    ]),
    ["account/read", "model/list"],
  );
  assert.equal(instances.length, 1);
  let unavailable = 0;
  manager.on("unavailable", () => unavailable++);
  await delay(40);
  assert.equal(manager.current, null);
  assert.equal(unavailable, 0);
  await manager.call("account/read");
  assert.equal(instances.length, 2);
  await manager.close();
});

test("keeps the child during generation, queued work or device login", async () => {
  let busy = true;
  const { manager } = fixture(() => busy);
  await manager.call("turn/start");
  const original = manager.current;
  await delay(50);
  assert.equal(manager.current, original);
  busy = false;
  await delay(40);
  assert.equal(manager.current, null);
  await manager.close();
});

test("does not stop pending RPC calls", async () => {
  const { manager, instances } = fixture();
  await manager.call("account/read");
  instances[0].call = async () => {
    await delay(50);
    return "done";
  };
  const pending = manager.call("model/list");
  await delay(30);
  assert.equal(manager.current, instances[0]);
  assert.equal(await pending, "done");
  await manager.close();
});

test("forwards generation events and unexpected failure", async () => {
  const { manager, instances } = fixture();
  await manager.call("turn/start");
  const received = [];
  manager.on("turn/completed", (event) => received.push(event));
  manager.on("unavailable", () => received.push("unavailable"));
  instances[0].emit("turn/completed", { threadId: "synthetic" });
  instances[0].child.emit("exit");
  assert.deepEqual(received, [{ threadId: "synthetic" }, "unavailable"]);
  await manager.close();
});

test("shutdown during startup stops the child and prevents new calls", async () => {
  const { manager } = fixture();
  const pending = manager.call("account/read");
  await manager.close();
  await pending;
  assert.equal(manager.current, null);
  await assert.rejects(manager.call("model/list"), /codex_unavailable/);
});

test("new requests wait for the old child to exit before starting another", async () => {
  const { manager, instances } = fixture();
  await manager.call("account/read");
  instances[0].child.kill = () => {
    setTimeout(() => instances[0].child.emit("exit"), 30);
  };
  const stopping = manager.stop();
  const pending = manager.call("model/list");
  await delay(10);
  assert.equal(instances.length, 1);
  await stopping;
  assert.equal(await pending, "model/list");
  assert.equal(instances.length, 2);
  await manager.close();
});

test("an initially paused queue can hold Codex without issuing an RPC", async () => {
  let queued = true;
  const { manager, instances } = fixture(() => queued);
  await manager.ensure();
  await delay(40);
  assert.equal(manager.current, instances[0]);
  queued = false;
  await delay(40);
  assert.equal(manager.current, null);
  await manager.close();
});
