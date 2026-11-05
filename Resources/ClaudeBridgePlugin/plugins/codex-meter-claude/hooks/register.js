// Claude Code's documented mods API. No credentials, prompts, transcripts or network access.
// https://code.claude.com/docs/en/plugins/mods/reference
// The native installer substitutes this one JSON string literal in its private copy
// when the app is installed somewhere else, such as ~/Applications.
const METER_EXECUTABLE = "/Applications/Codex Meter.app/Contents/MacOS/CodexMeter";

function normalize(limits, meterSource) {
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
  return { rate_limits: rateLimits, meterSource };
}

async function capture($, payload) {
  if (payload === undefined) return false;
  // The app enforces its own allowlist and writes the shared snapshot atomically,
  // mode 0600. Ignore subprocess output; it must never enter the conversation.
  const result = await $.process.run(
    [METER_EXECUTABLE, "--capture-claude-usage"],
    { stdin: JSON.stringify(payload), timeoutMs: 3000 }
  );
  return result.exitCode === 0;
}

async function captureCache($, state, isCurrent) {
  if (!isCurrent()) return;
  // This reads Claude Code's in-memory snapshot, not a server refresh. The
  // expected quota lets the native writer reject an older session's cache.
  const usage = await $.session.usage();
  const payload = normalize(usage?.rateLimits, "desktop-cache");
  if (!isCurrent() || payload === undefined) return;
  if (state.baseline !== undefined) payload.meterExpectedLimits = state.baseline;
  if (await capture($, payload) && isCurrent()) state.baseline = payload.rate_limits;
}

export function register(on) {
  // Serialize captures within this plugin instance so an older, slower observation
  // cannot overwrite a newer event. A failed capture must not poison this queue.
  let pending = Promise.resolve();
  function enqueue(capture) {
    pending = pending.then(capture).catch(() => {});
    return pending;
  }
  let timer;
  let generation = 0;
  let pollPending = false;
  const cache = { baseline: undefined };

  on("session.start", async ($, e, next) => {
    const current = ++generation;
    cache.baseline = undefined;
    try {
      timer?.cancel();
      // Register before the initial read, so a transient read failure can retry.
      timer = $.clock.every(60_000, async () => {
        if (current !== generation || pollPending) return;
        pollPending = true;
        try {
          // Coalesce ticks while any earlier read/capture is still queued.
          await enqueue(() => captureCache($, cache, () => current === generation));
        } finally {
          pollPending = false;
        }
      });
    } catch {
      // An unavailable clock must not block the initial read or the session.
    }
    await enqueue(() => captureCache($, cache, () => current === generation));
    return next(e);
  });

  on("session.attach", async ($, e, next) => {
    const current = generation;
    await enqueue(() => captureCache($, cache, () => current === generation));
    return next(e);
  });

  on("session.measure", async ($, e, next) => {
    // Clone only the quota fields before waiting for an earlier capture.
    try {
      const payload = normalize(e.rateLimits, "desktop-event");
      await enqueue(async () => {
        if (await capture($, payload)) cache.baseline = payload.rate_limits;
      });
    } catch {
      // Invalid input cannot block Claude Code or expose the original event.
    }
    return next(e);
  });

  on("session.end", async ($, e, next) => {
    // /clear and /resume also end a session without firing session.start again.
    // Keep polling across those transitions. The runtime cancels timers on unload.
    if (["logout", "prompt_input_exit", "other"].includes(e.reason)) {
      generation += 1;
      try { timer?.cancel(); } catch {}
      timer = undefined;
    }
    return next(e);
  });
}
