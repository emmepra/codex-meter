// Claude Code's documented mods API. No credentials, prompts, transcripts or network access.
// https://code.claude.com/docs/en/plugins/mods/reference
// The native installer substitutes this one JSON string literal in its private copy
// when the app is installed somewhere else, such as ~/Applications.
const METER_EXECUTABLE = "/Applications/Codex Meter.app/Contents/MacOS/CodexMeter";

function normalize(limits) {
  // An absent/malformed API result is not an authoritative empty reading.
  if (!Array.isArray(limits)) return undefined;
  const rateLimits = {};
  for (const row of limits) {
    if (!row || (row.kind !== "five_hour" && row.kind !== "seven_day")) continue;
    if (Object.hasOwn(rateLimits, row.kind)) continue;
    if (typeof row.percentUsed !== "number" || !Number.isFinite(row.percentUsed)
        || row.percentUsed < 0 || row.percentUsed > 100) continue;
    if (typeof row.resetsAt !== "string"
        || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(row.resetsAt)) continue;
    const reset = Date.parse(row.resetsAt) / 1000;
    if (!Number.isFinite(reset) || reset <= 0) continue;
    rateLimits[row.kind] = { used_percentage: row.percentUsed, resets_at: reset };
  }
  return { rate_limits: rateLimits };
}

async function capture($, payload) {
  if (payload === undefined) return;
  // The app enforces its own allowlist and writes the shared snapshot atomically,
  // mode 0600. Ignore subprocess output; it must never enter the conversation.
  await $.process.run(
    [METER_EXECUTABLE, "--capture-claude-usage"],
    { stdin: JSON.stringify(payload), timeoutMs: 3000 }
  );
}


export function register(on) {
  // Serialize captures within this plugin instance so an older, slower observation
  // cannot overwrite a newer event. A failed capture must not poison this queue.
  let pending = Promise.resolve();
  function enqueue(capture) {
    pending = pending.then(capture).catch(() => {});
    return pending;
  }

  on("session.start", async ($, e, next) => {
    await enqueue(async () => {
      const usage = await $.session.usage();
      await capture($, normalize(usage?.rateLimits));
    });
    return next(e);
  });

  on("session.measure", async ($, e, next) => {
    // Clone only the quota fields before waiting for an earlier capture.
    try {
      const payload = normalize(e.rateLimits);
      await enqueue(() => capture($, payload));
    } catch {
      // Invalid input cannot block Claude Code or expose the original event.
    }
    return next(e);
  });
}
