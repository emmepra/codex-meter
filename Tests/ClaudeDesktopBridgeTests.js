const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");

async function main() {
  const root = path.resolve(__dirname, "../Resources/ClaudeBridgePlugin");
  const source = await fs.readFile(path.join(root, "plugins/codex-meter-claude/hooks/register.js"), "utf8");
  // Claude Code treats hooks modules as ESM. A data URL gives Node the same
  // module semantics without adding a package.json to the application.
  const { register } = await import("data:text/javascript;base64," + Buffer.from(source).toString("base64"));
  const hooks = new Map();
  register((name, handler) => {
    assert(!hooks.has(name));
    hooks.set(name, handler);
  });
  assert.deepEqual([...hooks.keys()], ["session.start", "session.measure"]);
  const calls = [];
  let usage = { rateLimits: [] };
  let processError;
  let processBlock;
  const api = {
    session: { usage: async () => usage },
    process: { run: async (argv, options) => {
      calls.push({ argv, options });
      if (processBlock) await processBlock;
      if (processError) throw processError;
      return { exitCode: 0, stdout: "PRIVATE_OUTPUT", stderr: "PRIVATE_ERROR" };
    } }
  };
  const nextEvents = [];
  const next = async e => { nextEvents.push(e); return { continued: true }; };
  const row = (percentUsed, kind = "five_hour") => ({ kind, percentUsed, resetsAt: "2026-11-06T12:00:00.000Z" });
  const measure = (rateLimits) => hooks.get("session.measure")(api, { rateLimits }, next);

  usage = { rateLimits: [
    { ...row(0), account: "PRIVATE_ACCOUNT", project: "PRIVATE_PROJECT" },
    row(68.5, "seven_day"), row(90, "seven_day_opus"), row(99, "spend_limit")
  ], transcript: "PRIVATE_TRANSCRIPT", cost: { usd: 9 } };
  assert.deepEqual(await hooks.get("session.start")(api, { secret: "PRIVATE_EVENT" }, next), { continued: true });
  assert.deepEqual(calls[0].argv, ["/Applications/Codex Meter.app/Contents/MacOS/CodexMeter", "--capture-claude-usage"]);
  assert.equal(calls[0].options.timeoutMs, 3000);
  const first = JSON.parse(calls[0].options.stdin);
  assert.deepEqual(first, { rate_limits: {
    five_hour: { used_percentage: 0, resets_at: Date.parse("2026-11-06T12:00:00.000Z") / 1000 },
    seven_day: { used_percentage: 68.5, resets_at: Date.parse("2026-11-06T12:00:00.000Z") / 1000 }
  } });
  assert(!JSON.stringify(calls).includes("PRIVATE"), "Subprocess input must not contain unrelated values");

  await measure([row(25), row(90)]);
  assert.equal(JSON.parse(calls.at(-1).options.stdin).rate_limits.five_hour.used_percentage, 25, "Use one known reading per window");
  await measure([row(true), row("5"), row(NaN), row(Infinity), row(-1), row(101),
    { ...row(1), resetsAt: "not a date" }, { ...row(1), resetsAt: 1800000000 }]);
  assert.deepEqual(JSON.parse(calls.at(-1).options.stdin), { rate_limits: {} }, "Invalid readings never become quota");
  await measure([]);
  assert.deepEqual(JSON.parse(calls.at(-1).options.stdin), { rate_limits: {} }, "Empty authoritative readings clear old quota");
  const beforeMalformed = calls.length;
  await measure(undefined);
  await measure({ five_hour: 20 });
  assert.equal(calls.length, beforeMalformed, "Malformed responses must not erase a prior reading");

  // Slow initial API reads cannot allow a subsequent event to write first.
  let releaseUsage;
  api.session.usage = () => new Promise(resolve => { releaseUsage = resolve; });
  const start = hooks.get("session.start")(api, {}, next);
  await Promise.resolve();
  const later = measure([row(70)]);
  const beforeRelease = calls.length;
  await Promise.resolve();
  assert.equal(calls.length, beforeRelease);
  releaseUsage({ rateLimits: [row(60)] });
  await Promise.all([start, later]);
  assert.deepEqual(calls.slice(-2).map(c => JSON.parse(c.options.stdin).rate_limits.five_hour.used_percentage), [60, 70]);

  // A slow subprocess also keeps subsequent captures serialized.
  let releaseProcess;
  processBlock = new Promise(resolve => { releaseProcess = resolve; });
  const blocked = measure([row(71)]);
  await Promise.resolve();
  const waiting = measure([row(72)]);
  const whileBlocked = calls.length;
  await Promise.resolve();
  assert.equal(calls.length, whileBlocked);
  processBlock = undefined;
  releaseProcess();
  await Promise.all([blocked, waiting]);
  assert.deepEqual(calls.slice(-2).map(c => JSON.parse(c.options.stdin).rate_limits.five_hour.used_percentage), [71, 72]);

  // Failures stay out of the transcript and cannot poison the next capture.
  processError = new Error("PRIVATE_PROCESS_FAILURE");
  assert.deepEqual(await measure([row(80)]), { continued: true });
  processError = undefined;
  await measure([row(81)]);
  assert.equal(JSON.parse(calls.at(-1).options.stdin).rate_limits.five_hour.used_percentage, 81);
  const beforeApiError = calls.length;
  api.session.usage = async () => { throw new Error("PRIVATE_API_FAILURE"); };
  assert.deepEqual(await hooks.get("session.start")(api, {}, next), { continued: true });
  assert.equal(calls.length, beforeApiError, "An API error must not clear the latest observation");
  await measure([row(82)]);
  assert.equal(JSON.parse(calls.at(-1).options.stdin).rate_limits.five_hour.used_percentage, 82);
  assert.equal(nextEvents.length, 14, "Every observed event continues through the remaining handlers exactly once");

  const marketplace = JSON.parse(await fs.readFile(path.join(root, ".claude-plugin/marketplace.json"), "utf8"));
  const plugin = JSON.parse(await fs.readFile(path.join(root, "plugins/codex-meter-claude/.claude-plugin/plugin.json"), "utf8"));
  const hookConfig = JSON.parse(await fs.readFile(path.join(root, "plugins/codex-meter-claude/hooks/hooks.json"), "utf8"));
  assert.equal(marketplace.plugins[0].name, plugin.name);
  assert.deepEqual(hookConfig.modules, ["./register.js"]);
  console.log("Claude Desktop bridge tests passed");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
