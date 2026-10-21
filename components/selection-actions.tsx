"use client";

import { createContext, useContext } from "react";

/**
 * What a piece of the transcript can do with its own text.
 *
 * The selection toolbar offers these two on a passage the reader selected; a
 * code block offers them on the block it already knows the text of. Both end in
 * the same two actions, so the labels are the ones the toolbar uses.
 */
export interface SelectionActions {
  /** The project the new session (or task) belongs to. */
  cwd: string;
  /** Runs `text` as the first prompt of a brand-new session in this window. */
  runInNewSession: (text: string) => void;
  /** Opens Settings › Scheduled tasks' new-task form on `text`. */
  newScheduledTask: (text: string) => void;
}

/**
 * Provided around the chat by AppShell. Outside it — the file viewer renders the
 * same code blocks for a README — there is no provider, and no buttons: a file
 * being read is not a place to start a session from.
 */
export const SelectionActionsContext = createContext<SelectionActions | null>(null);

export function useSelectionActions(): SelectionActions | null {
  return useContext(SelectionActionsContext);
}
