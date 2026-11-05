const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");

class FakeClock {
  timers = [];
  every(milliseconds, callback) {
    const timer = { milliseconds, callback, active: true, cancellations: 0 };
    timer.handle = { cancel: () => { timer.active = false; timer.cancellations += 1; } };
    this.timers.push(timer);
    return timer.handle;
  }
  get active() { return this.timers.filter(timer => timer.active); }
  tick() { return Promise.all(this.active.map(timer => timer.callback())); }
  // The mods runtime owns timer cleanup when its module is unloaded.
  unload() { for (const timer of this.active) timer.handle.cancel(); }
}

const row = (percentUsed, kind = "five_hour") => ({
  kind, percentUsed, resetsAt: "2026-11-06T12:00:00.000Z"
});
const flush = () => new Promise(resolve => setImmediate(resolve));
function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

async function main() {
  const root = path.resolve(__dirname, "../Resources/ClaudeBridgePlugin");
  const source = await fs.readFile(path.join(root, "plugins/codex-meter-claude/hooks/register.js"), "utf8");
  // Load the production hooks with the same ES module semantics as Claude Code.
  const { register } = await import("data:text/javascript;base64," + Buffer.from(source).toString("base64"));
  function harness() {
    const hooks = new Map();
    register((name, handler) => {
      assert(!hooks.has(name));
      hooks.set(name, handler);
    });
    assert.deepEqual([...hooks.keys()], ["session.start", "session.attach", "session.measure", "session.end"]);
    const calls = [];
    const clock = new FakeClock();
    const state = { usage: { rateLimits: [] }, reads: 0, activeWrites: 0, maximumWrites: 0 };
    const api = {
      clock,
      session: { usage: async () => {
        state.reads += 1;
        if (state.usageError) throw state.usageError;
        return state.read ? state.read() : state.usage;
      } },
      process: { run: async (argv, options) => {
        calls.push({ argv, options });
        state.activeWrites += 1;
        state.maximumWrites = Math.max(state.maximumWrites, state.activeWrites);
        try {
          if (state.processBlock) await state.processBlock;
          if (state.processError) throw state.processError;
          return { exitCode: state.exitCode ?? 0, stdout: "PRIVATE_OUTPUT", stderr: "PRIVATE_ERROR" };
        } finally { state.activeWrites -= 1; }
      } }
    };
    async function emit(name, event = {}) {
      let nextCalls = 0;
      const result = await hooks.get(name)(api, event, async received => {
        nextCalls += 1;
        assert.strictEqual(received, event, "Continue the original event unchanged");
        return { continued: true };
      });
      assert.deepEqual(result, { continued: true });
      assert.equal(nextCalls, 1, "Every event must continue exactly once, including on failures");
    }
    return {
      hooks, api, calls, clock, state, emit,
      measure: rateLimits => emit("session.measure", { rateLimits }),
      payloads: () => calls.map(call => JSON.parse(call.options.stdin)),
      latest: () => JSON.parse(calls.at(-1).options.stdin)
    };
  }

  const h = harness();
  h.state.usage = { rateLimits: [
    { ...row(0), account: "PRIVATE_ACCOUNT", project: "PRIVATE_PROJECT" },
    row(68.5, "seven_day"), row(90, "seven_day_opus"), row(99, "spend_limit")
  ], transcript: "PRIVATE_TRANSCRIPT", cost: { usd: 9 } };
  await h.emit("session.start", { secret: "PRIVATE_EVENT" });
  assert.equal(h.clock.active.length, 1);
  assert.equal(h.clock.active[0].milliseconds, 60_000);
  assert.deepEqual(h.calls[0].argv, ["/Applications/Codex Meter.app/Contents/MacOS/CodexMeter", "--capture-claude-usage"]);
  assert.equal(h.calls[0].options.timeoutMs, 3000);
  assert.deepEqual(h.latest(), { rate_limits: {
    five_hour: { used_percentage: 0, resets_at: Date.parse(row(0).resetsAt) / 1000 },
    seven_day: { used_percentage: 68.5, resets_at: Date.parse(row(0).resetsAt) / 1000 }
  }, meterSource: "desktop-cache" });
  assert(!JSON.stringify(h.calls).includes("PRIVATE"), "Capture input must not include unrelated API or event fields");

  // While idle, each tick rereads the current cached API value, even if unchanged.
  h.state.usage = { rateLimits: [row(25)] };
  const beforeIdle = h.calls.length;
  await h.clock.tick();
  assert.equal(h.calls.length, beforeIdle + 1);
  assert.equal(h.latest().rate_limits.five_hour.used_percentage, 25);
  assert.equal(h.latest().meterSource, "desktop-cache");
  const unchanged = h.latest();
  await h.clock.tick();
  assert.deepEqual(h.latest().rate_limits, unchanged.rate_limits);
  assert.deepEqual(h.latest().meterExpectedLimits, unchanged.rate_limits, "Polls identify only the last acknowledged quota");
  assert.equal(h.latest().meterSource, "desktop-cache", "An unchanged cache is never a new server event");
  assert.equal(h.calls.length, beforeIdle + 2);
  h.state.usage = { rateLimits: [row(26)] };
  const timerBeforeAttach = h.clock.active[0];
  await h.emit("session.attach", { surface: "PRIVATE_SURFACE" });
  assert.equal(h.latest().rate_limits.five_hour.used_percentage, 26);
  assert.equal(h.latest().meterSource, "desktop-cache");
  assert.strictEqual(h.clock.active[0], timerBeforeAttach, "Attach sync must not create another timer");

  await h.measure([row(27), row(90)]);
  assert.equal(h.latest().rate_limits.five_hour.used_percentage, 27, "Use one valid reading per supported window");
  assert.equal(h.latest().meterSource, "desktop-event");
  await h.measure([row(true), row("5"), row(NaN), row(Infinity), row(-1), row(101),
    { ...row(1), resetsAt: "not a date" }, { ...row(1), resetsAt: 1800000000 }]);
  assert.deepEqual(h.latest(), { rate_limits: {}, meterSource: "desktop-event" });
  await h.measure([]);
  assert.deepEqual(h.latest(), { rate_limits: {}, meterSource: "desktop-event" }, "An authoritative empty list clears quota");
  const beforeMalformed = h.calls.length;
  await h.measure(undefined);
  await h.measure({ five_hour: 20 });
  h.state.usage = { rateLimits: "malformed", private: "PRIVATE_RESPONSE" };
  await h.clock.tick();
  assert.equal(h.calls.length, beforeMalformed, "Malformed inputs must not erase prior quota");

  // A failed initial read still registers polling and retries without another event.
  const retry = harness();
  retry.state.usageError = new Error("PRIVATE_API_FAILURE");
  await retry.emit("session.start");
  assert.equal(retry.clock.active.length, 1);
  assert.equal(retry.calls.length, 0);
  retry.state.usageError = undefined;
  retry.state.usage = { rateLimits: [row(41)] };
  await retry.clock.tick();
  assert.equal(retry.latest().rate_limits.five_hour.used_percentage, 41);
  retry.state.processError = new Error("PRIVATE_PROCESS_FAILURE");
  await retry.clock.tick();
  retry.state.processError = undefined;
  retry.state.usage = { rateLimits: [row(42)] };
  await retry.clock.tick();
  assert.equal(retry.latest().rate_limits.five_hour.used_percentage, 42, "A failed capture must not poison the queue");
  retry.state.usageError = new Error("PRIVATE_API_FAILURE");
  await retry.emit("session.attach");
  await retry.measure([row(43)]);
  assert.equal(retry.latest().rate_limits.five_hour.used_percentage, 43);

  // Another session may supersede this cache. A refused write must not advance
  // its baseline, so retries cannot overwrite the newer session's observation.
  const conflict = harness();
  conflict.state.usage = { rateLimits: [row(10)] };
  await conflict.emit("session.start");
  const acknowledged = conflict.latest().rate_limits;
  conflict.state.exitCode = 1;
  conflict.state.usage = { rateLimits: [row(20)] };
  await conflict.clock.tick();
  conflict.state.exitCode = 0;
  conflict.state.usage = { rateLimits: [row(30)] };
  await conflict.clock.tick();
  assert.deepEqual(conflict.latest().meterExpectedLimits, acknowledged);
  await conflict.clock.tick();
  assert.deepEqual(conflict.latest().meterExpectedLimits, conflict.latest().rate_limits);

  // Repeated starts replace the timer; clear/resume must not stop it permanently.
  const firstTimer = retry.clock.active[0];
  retry.state.usageError = undefined;
  await retry.emit("session.start");
  assert.equal(firstTimer.cancellations, 1);
  assert.equal(retry.clock.active.length, 1);
  for (const reason of ["clear", "resume"]) {
    await retry.emit("session.end", { reason });
    assert.equal(retry.clock.active.length, 1);
    const previousCalls = retry.calls.length;
    await retry.clock.tick();
    assert.equal(retry.calls.length, previousCalls + 1, "Polling must survive clear/resume without a new session.start");
  }

  // A slow initial API read and a later event preserve their observation order.
  const initial = harness();
  const initialRead = deferred();
  initial.state.read = () => initialRead.promise;
  const start = initial.emit("session.start");
  await flush();
  assert.equal(initial.clock.active.length, 1, "Register the timer before waiting for the initial read");
  const later = initial.measure([row(70)]);
  assert.equal(initial.calls.length, 0);
  initialRead.resolve({ rateLimits: [row(60)] });
  await Promise.all([start, later]);
  assert.deepEqual(initial.payloads().map(p => p.rate_limits.five_hour.used_percentage), [60, 70]);

  // Coalesce any number of ticks behind one cached read; never grow an idle queue.
  const busy = harness();
  busy.state.usage = { rateLimits: [row(1)] };
  await busy.emit("session.start");
  const read = deferred();
  busy.state.read = () => read.promise;
  const readsBefore = busy.state.reads;
  const poll = busy.clock.tick();
  await flush();
  const measurement = busy.measure([row(81)]);
  await Promise.all(Array.from({ length: 100 }, () => busy.clock.tick()));
  assert.equal(busy.state.reads, readsBefore + 1);
  assert.equal(busy.calls.length, 1);
  read.resolve({ rateLimits: [row(80)] });
  await Promise.all([poll, measurement]);
  assert.deepEqual(busy.payloads().slice(-2).map(p => p.rate_limits.five_hour.used_percentage), [80, 81]);
  const afterCoalescing = busy.calls.length;
  await flush();
  assert.equal(busy.calls.length, afterCoalescing, "Skipped ticks must not leave a backlog after the read finishes");
  busy.state.read = undefined;
  busy.state.usage = { rateLimits: [row(82)] };
  await busy.clock.tick();
  assert.equal(busy.latest().rate_limits.five_hour.used_percentage, 82);

  // Blocked subprocesses also serialize cache and measure captures.
  const blockedWrite = deferred();
  busy.state.processBlock = blockedWrite.promise;
  const blocked = busy.measure([row(83)]);
  await flush();
  const whileBlocked = busy.calls.length;
  const waitingPoll = busy.clock.tick();
  const waitingEvent = busy.measure([row(85)]);
  await Promise.all(Array.from({ length: 100 }, () => busy.clock.tick()));
  assert.equal(busy.calls.length, whileBlocked);
  busy.state.processBlock = undefined;
  busy.state.usage = { rateLimits: [row(84)] };
  blockedWrite.resolve();
  await Promise.all([blocked, waitingPoll, waitingEvent]);
  assert.deepEqual(busy.payloads().slice(-3).map(p => p.rate_limits.five_hour.used_percentage), [83, 84, 85]);
  assert.equal(busy.state.maximumWrites, 1, "A slow write must never allow another capture to overtake it");

  // True shutdown cancels polling, including a cached read already in flight.
  for (const reason of ["logout", "prompt_input_exit", "other"]) {
    const stopped = harness();
    stopped.state.usage = { rateLimits: [row(50)] };
    await stopped.emit("session.start");
    const read = deferred();
    stopped.state.read = () => read.promise;
    const inFlight = stopped.clock.tick();
    await flush();
    await stopped.emit("session.end", { reason });
    assert.equal(stopped.clock.active.length, 0);
    read.resolve({ rateLimits: [row(99)] });
    await inFlight;
    await stopped.clock.tick();
    assert.equal(stopped.calls.length, 1, "An ended session must not publish a delayed cached observation");
  }
  const unloaded = harness();
  await unloaded.emit("session.start");
  unloaded.clock.unload();
  await unloaded.clock.tick();
  assert.equal(unloaded.clock.active.length, 0);
  assert.equal(unloaded.calls.length, 1, "Runtime-owned timers stop on unload without an invented unload event");

  let nextCalls = 0;
  await assert.rejects(h.hooks.get("session.measure")(h.api, { rateLimits: [] }, async () => {
    nextCalls += 1;
    throw new Error("downstream");
  }), /downstream/);
  assert.equal(nextCalls, 1, "Never catch and retry next() itself");
  for (const payload of [...h.payloads(), ...retry.payloads(), ...busy.payloads()]) {
    assert.deepEqual(Object.keys(payload).filter(key => key !== "meterExpectedLimits").sort(), ["meterSource", "rate_limits"]);
    assert(["desktop-cache", "desktop-event"].includes(payload.meterSource));
    for (const limits of [payload.rate_limits, payload.meterExpectedLimits].filter(Boolean)) {
      for (const [kind, value] of Object.entries(limits)) {
        assert(["five_hour", "seven_day"].includes(kind));
        assert.deepEqual(Object.keys(value).sort(), ["resets_at", "used_percentage"]);
      }
    }
  }
  assert(!JSON.stringify([...h.calls, ...retry.calls, ...busy.calls]).includes("PRIVATE"));

  const marketplace = JSON.parse(await fs.readFile(path.join(root, ".claude-plugin/marketplace.json"), "utf8"));
  const plugin = JSON.parse(await fs.readFile(path.join(root, "plugins/codex-meter-claude/.claude-plugin/plugin.json"), "utf8"));
  const hookConfig = JSON.parse(await fs.readFile(path.join(root, "plugins/codex-meter-claude/hooks/hooks.json"), "utf8"));
  assert.equal(marketplace.plugins[0].name, plugin.name);
  assert.equal(plugin.version, "0.1.1");
  assert.deepEqual(hookConfig.modules, ["./register.js"]);
  console.log("Claude Desktop bridge tests passed");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
