export interface ExtensionUrlRule {
  pattern: string;
  action: "block" | "allow";
  exceptions: Array<{ pattern: string }>;
}

export interface DNRRule {
  id: number;
  priority: number;
  action: { type: "block" | "allow" };
  condition: { urlFilter: string; resourceTypes: chrome.declarativeNetRequest.ResourceType[] };
}

const RESOURCE_TYPES = [
  "main_frame",
  "sub_frame",
] as chrome.declarativeNetRequest.ResourceType[];

/**
 * Builds Chrome declarativeNetRequest rules from the extension URL rules
 * produced by the StiraPolicy.
 *
 * - Each block entry produces one block rule (priority=1).
 * - Each exception within a block entry produces one allow rule (priority=2).
 * - Allow rules have strictly higher priority than block rules so exceptions
 *   are honoured (e.g. youtube.com blocked, youtube.com/watch allowed).
 * - Rule IDs start at 1 and increment; all IDs are unique positive integers.
 */
export function buildDNRRules(urlRules: ExtensionUrlRule[]): DNRRule[] {
  const result: DNRRule[] = [];
  let nextId = 1;

  for (const rule of urlRules) {
    if (rule.action === "block") {
      // Block rule for the whole domain/pattern
      result.push({
        id: nextId++,
        priority: 1,
        action: { type: "block" },
        condition: {
          urlFilter: rule.pattern,
          resourceTypes: RESOURCE_TYPES,
        },
      });

      // Allow rules for each exception (higher priority overrides the block)
      for (const exception of rule.exceptions) {
        result.push({
          id: nextId++,
          priority: 2,
          action: { type: "allow" },
          condition: {
            urlFilter: exception.pattern,
            resourceTypes: RESOURCE_TYPES,
          },
        });
      }
    }
  }

  return result;
}
