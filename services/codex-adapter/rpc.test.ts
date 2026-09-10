import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import test from "node:test";
import { CodexRpc } from "./rpc.ts";
function fixture() {
  const child = Object.assign(new EventEmitter(), {
    stdin: new PassThrough(),
    stdout: new PassThrough(),
    stderr: new PassThrough(),
  });
  const sent = [];
  child.stdin.on("data", (chunk) => sent.push(JSON.parse(chunk.toString())));
  return { child, sent, rpc: new CodexRpc(child) };
}
test("matches out-of-order replies to the correct request", async () => {
  const { child, rpc, sent } = fixture();
  const first = rpc.call("account/read");
  const second = rpc.call("model/list");
  child.stdout.write(
    `${JSON.stringify({ id: sent[1].id, result: { models: [] } })}\n`,
  );
  child.stdout.write(
    `${JSON.stringify({ id: sent[0].id, result: { account: null } })}\n`,
  );
  assert.deepEqual(await first, { account: null });
  assert.deepEqual(await second, { models: [] });
});
test("does not leak raw upstream errors", async () => {
  const { child, rpc, sent } = fixture();
  const result = rpc.call("account/read");
  child.stdout.write(
    `${JSON.stringify({ id: sent[0].id, error: { message: "secret token" } })}\n`,
  );
  await assert.rejects(result, { message: "codex_request_failed" });
});
test("rejects host tool execution requests", () => {
  const { child, sent } = fixture();
  child.stdout.write(
    `${JSON.stringify({
      id: 99,
      method: "item/commandExecution/requestApproval",
      params: { command: "cat /data/codex/auth.json" },
    })}\n`,
  );
  assert.equal(sent[0].error.code, -32601);
});
test("process exit rejects pending calls", async () => {
  const { child, rpc } = fixture();
  const result = rpc.call("account/read");
  child.emit("exit", 1);
  await assert.rejects(result, { message: "codex_unavailable" });
});
test("timeouts remove pending requests", async () => {
  const { rpc } = fixture();
  await assert.rejects(rpc.call("account/read", {}, 5), {
    message: "codex_timeout",
  });
  assert.equal(rpc.pending.size, 0);
});
