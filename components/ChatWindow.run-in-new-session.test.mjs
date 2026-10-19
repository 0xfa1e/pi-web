import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const chatSource = await readFile(new URL("./ChatWindow.tsx", import.meta.url), "utf8");
const shellSource = await readFile(new URL("./AppShell.tsx", import.meta.url), "utf8");

test("the selection toolbar offers the new-session run without needing a forked entry", () => {
  // The two buttons before it quote into a composer and fork at an assistant
  // entry; the selection itself is the prompt here, so any selection qualifies.
  const button = chatSource.match(/\{onRunInNewSession && \(session\?\.cwd \?\? newSessionCwd\) && \([\s\S]*?chat\.runInNewSession[\s\S]*?\n          \)\}/);
  assert.ok(button, "expected the new-session button gated on a working directory");
  assert.ok(
    !button[0].includes("sourceEntryId"),
    "the new-session button must not require the selection to come from an assistant entry",
  );
});

test("the new-session run creates the session and shows it in this window", () => {
  const handler = shellSource.match(/const handleRunInNewSession = useCallback\([\s\S]*?\n  \}, \[openCreatedSession\]\);/);
  assert.ok(handler, "expected the handleRunInNewSession handler");
  assert.match(handler[0], /fetch\("\/api\/agent\/new"/);
  assert.match(handler[0], /type: "prompt"/);
  assert.match(handler[0], /message: prompt/);
  // The composer's own new-session flow: select the id the server returned.
  assert.match(handler[0], /openCreatedSession\(body\.sessionId\)/);
  assert.ok(
    !handler[0].includes("window.open"),
    "the run must not open a browser window; it behaves like the sidebar's New session",
  );
});
