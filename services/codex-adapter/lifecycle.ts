import { EventEmitter } from "node:events";

// Keep the HTTP service available while Codex is stopped. Credentials stay in
// CODEX_HOME; idle shutdown is deliberately not account/logout.
export class LazyRpc extends EventEmitter {
  current = null;
  starting = null;
  stopping = null;
  timer = null;
  calls = 0;
  closed = false;

  constructor(createRpc, busy, idleMs = 60000) {
    super();
    this.createRpc = createRpc;
    this.busy = busy;
    this.idleMs = idleMs;
  }

  async ensure() {
    if (this.closed) throw new Error("codex_unavailable");
    if (this.stopping) await this.stopping;
    if (this.closed) throw new Error("codex_unavailable");
    if (this.current) return this.current;
    if (!this.starting) {
      this.starting = (async () => {
        const rpc = this.createRpc();
        for (const event of [
          "account/login/completed",
          "item/agentMessage/delta",
          "turn/completed",
        ])
          rpc.on(event, (params) => this.emit(event, params));
        rpc.on("unavailable", () => {
          if (this.current === rpc) {
            this.current = null;
            this.emit("unavailable");
          }
        });
        try {
          await rpc.initialize();
          this.current = rpc;
          this.schedule();
          return rpc;
        } catch (error) {
          rpc.child.kill("SIGTERM");
          throw error;
        }
      })().finally(() => {
        this.starting = null;
      });
    }
    return this.starting;
  }

  async call(...args) {
    this.calls++;
    clearTimeout(this.timer);
    try {
      return await (await this.ensure()).call(...args);
    } finally {
      this.calls--;
      this.schedule();
    }
  }

  schedule() {
    clearTimeout(this.timer);
    if (this.closed || !this.current) return;
    this.timer = setTimeout(() => {
      if (this.calls || this.busy()) this.schedule();
      else void this.stop();
    }, this.idleMs);
    this.timer.unref();
  }

  async stop() {
    clearTimeout(this.timer);
    const rpc = this.current;
    if (!rpc) return this.stopping;
    this.current = null; // An intentional exit must not fail the HTTP service.
    this.stopping = new Promise((resolve) => {
      const force = setTimeout(() => rpc.child.kill("SIGKILL"), 5000);
      force.unref();
      rpc.child.once("exit", () => {
        clearTimeout(force);
        resolve();
      });
      rpc.child.kill("SIGTERM");
    });
    try {
      await this.stopping;
    } finally {
      this.stopping = null;
    }
  }

  async close() {
    this.closed = true;
    if (this.starting) await this.starting.catch(() => {});
    await this.stop();
  }
}
