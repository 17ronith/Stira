import { buildDNRRules, DNRRule } from "../rules/rule_builder";

const NATIVE_HOST = "com.stira.extensionbridge";
const SESSION_TOKEN = "stira-session";

interface ExtensionUrlRuleEntry {
  pattern: string;
  action: "block" | "allow";
  exceptions: Array<{ pattern: string }>;
}

interface PolicyMessage {
  type: "policy";
  session_token: string;
  rules: ExtensionUrlRuleEntry[];
}

interface PolicyUpdateMessage {
  type: "policy_update";
  rules: ExtensionUrlRuleEntry[];
}

interface SessionEndedMessage {
  type: "session_ended";
}

type IncomingMessage = PolicyMessage | PolicyUpdateMessage | SessionEndedMessage;

let nativePort: chrome.runtime.Port | null = null;

/**
 * Apply a set of DNR rules by removing all existing dynamic rules first,
 * then adding the new ones.
 */
async function applyDNRRules(rules: DNRRule[]): Promise<void> {
  const existing = await chrome.declarativeNetRequest.getDynamicRules();
  const removeRuleIds = existing.map((r) => r.id);
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds,
    addRules: rules,
  });
}

/**
 * Remove all dynamic DNR rules (called when session ends or connection drops).
 */
async function clearAllRules(): Promise<void> {
  const existing = await chrome.declarativeNetRequest.getDynamicRules();
  const removeRuleIds = existing.map((r) => r.id);
  if (removeRuleIds.length > 0) {
    await chrome.declarativeNetRequest.updateDynamicRules({
      removeRuleIds,
      addRules: [],
    });
  }
}

/**
 * Handle an incoming message from the native messaging host.
 */
function handleNativeMessage(message: IncomingMessage): void {
  if (message.type === "policy") {
    const dnrRules = buildDNRRules(message.rules);
    applyDNRRules(dnrRules).catch((err: unknown) => {
      console.error("[Stira] Failed to apply policy rules:", err);
    });
  } else if (message.type === "policy_update") {
    const dnrRules = buildDNRRules(message.rules);
    applyDNRRules(dnrRules).catch((err: unknown) => {
      console.error("[Stira] Failed to apply updated policy rules:", err);
    });
  } else if (message.type === "session_ended") {
    clearAllRules().catch((err: unknown) => {
      console.error("[Stira] Failed to clear rules on session end:", err);
    });
  }
}

/**
 * Connect to the native messaging host, request the current policy,
 * and set up listeners for subsequent policy updates.
 */
function connectAndRequestPolicy(): void {
  // Disconnect any existing port before opening a new one
  if (nativePort !== null) {
    nativePort.disconnect();
    nativePort = null;
  }

  const port = chrome.runtime.connectNative(NATIVE_HOST);
  nativePort = port;

  port.onMessage.addListener((message: IncomingMessage) => {
    handleNativeMessage(message);
  });

  port.onDisconnect.addListener(() => {
    const lastError = chrome.runtime.lastError;
    if (lastError) {
      console.error("[Stira] Native messaging host disconnected:", lastError.message);
    } else {
      console.log("[Stira] Native messaging host disconnected gracefully.");
    }
    nativePort = null;
    // Clear rules so no stale blocks remain if the host dies unexpectedly
    clearAllRules().catch((err: unknown) => {
      console.error("[Stira] Failed to clear rules after disconnect:", err);
    });
  });

  // Request the current policy immediately after connecting
  port.postMessage({ type: "get_policy", session_token: SESSION_TOKEN });
}

// On browser startup: connect and request current policy
chrome.runtime.onStartup.addListener(() => {
  connectAndRequestPolicy();
});

// On extension install/update: connect and request current policy
chrome.runtime.onInstalled.addListener(() => {
  connectAndRequestPolicy();
});
