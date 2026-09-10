import { EventEmitter } from "node:events";
import { createInterface } from "node:readline";

export function safeError(error) {
  const message = String(error?.message || "");
  if (
    /\b401\b|unauthorized|authentication|refresh[_ ]token|sign.in required/i.test(
      message,
    )
  )
    return new Error("not_connected");
  if (/\b429\b|quota exceeded|usage limit|rate limit/i.test(message))
    return new Error("quota_exhausted");
  return new Error("codex_request_failed");
}

// Never forward raw RPC errors: upstream diagnostics can contain credentials.
export class CodexRpc extends EventEmitter {
  child;
  sequence = 0;
  pending = new Map();
  ready = false;

  constructor(child) {
    super();
    this.child = child;
    const lines = createInterface({ input: child.stdout });
    lines.on("line", (line) => {
      let message = null;
      try {
        message = JSON.parse(line);
      } catch {
        return;
      }
      if (message.method && message.id !== undefined) {
        // This integration never grants Codex permission to execute host tools.
        this.send({
          id: message.id,
          error: { code: -32601, message: "Host tools are disabled" },
        });
      } else if (message.id !== undefined) {
        const pending = this.pending.get(message.id);
        if (!pending) return;
        clearTimeout(pending.timer);
        this.pending.delete(message.id);
        if (message.error) pending.reject(safeError(message.error));
        else pending.resolve(message.result);
      } else if (message.method) {
        this.emit(message.method, message.params);
      }
    });
    const unavailable = () => {
      this.ready = false;
      for (const pending of this.pending.values()) {
        clearTimeout(pending.timer);
        pending.reject(new Error("codex_unavailable"));
      }
      this.pending.clear();
      this.emit("unavailable");
    };
    child.on("exit", unavailable);
    child.on("error", unavailable);
    child.stdin.on("error", unavailable);
    child.stderr.resume(); // Do not log upstream diagnostics or authentication data.
  }

  send(message) {
    this.child.stdin.write(`${JSON.stringify(message)}\n`);
  }

  call(method, params = {}, timeout = 30_000) {
    return new Promise((resolve, reject) => {
      const id = ++this.sequence;
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("codex_timeout"));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      this.send({ id, method, params });
    });
  }

  async initialize() {
    await this.call("initialize", {
      clientInfo: {
        name: "sure_personal_finance",
        title: "Sure",
        version: "0.1.0",
      },
    });
    this.send({ method: "initialized", params: {} });
    this.ready = true;
  }
}
