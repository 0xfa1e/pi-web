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

test("the selection toolbar can start a scheduled task instead", () => {
  const button = chatSource.match(/\{onNewScheduledTask && \(session\?\.cwd \?\? newSessionCwd\) && \([\s\S]*?chat\.newScheduledTask[\s\S]*?\n          \)\}/);
  assert.ok(button, "expected the new-scheduled-task button gated on a working directory");
  // Settings opens on its new-task form, which is filled from the handler below.
  const handler = shellSource.match(/const handleNewScheduledTask = useCallback\([\s\S]*?\n  \}, \[\]\);/);
  assert.ok(handler, "expected the handleNewScheduledTask handler");
  assert.match(handler[0], /setSchedulePrompt\(prompt\)/);
  assert.match(handler[0], /setSettingsSection\("schedules"\)/);
  const panel = shellSource.match(/schedulePrompt=\{schedulePrompt\}[\s\S]{0,120}/);
  assert.ok(panel, "expected SettingsPanel to receive the prompt");
  assert.match(panel[0], /onSchedulePromptConsumed=/);
});

test("a code block offers both actions on its own text", async () => {
  const codeSource = await readFile(new URL("./MermaidBlock.tsx", import.meta.url), "utf8");
  const block = codeSource.match(/export const CodeBlock = memo\(function CodeBlock[\s\S]*?\n\}\);/);
  assert.ok(block, "expected the CodeBlock component");
  assert.match(block[0], /useSelectionActions\(\)/, "the block must read the chat's actions from context");
  assert.match(block[0], /runInNewSession\(code\)/);
  assert.match(block[0], /newScheduledTask\(code\)/);
  // Half a prompt is worse than none: the buttons wait for the block to finish.
  assert.match(block[0], /\{selectionActions && !isStreaming && \(/);

  // The provider is the chat's, so the file viewer's code blocks stay read-only.
  assert.match(shellSource, /<SelectionActionsContext\.Provider value=\{selectionActions\}>[\s\S]{0,200}<ChatWindow/);
});
