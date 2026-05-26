import { buildDNRRules } from "../rules/rule_builder";

describe("buildDNRRules", () => {
  // Test 1: Single blocked domain produces one block rule
  it("single blocked domain produces one block rule", () => {
    const rules = buildDNRRules([
      { pattern: "twitter.com", action: "block", exceptions: [] },
    ]);
    expect(rules).toHaveLength(1);
    expect(rules[0].action.type).toBe("block");
    expect(rules[0].condition.urlFilter).toBe("twitter.com");
    expect(rules[0].condition.resourceTypes).toEqual(["main_frame", "sub_frame"]);
  });

  // Test 2: Blocked domain with one exception produces block rule + allow rule
  it("blocked domain with one exception produces block rule + allow rule", () => {
    const rules = buildDNRRules([
      {
        pattern: "youtube.com",
        action: "block",
        exceptions: [{ pattern: "youtube.com/watch" }],
      },
    ]);
    expect(rules).toHaveLength(2);
    const blockRule = rules.find((r) => r.action.type === "block");
    const allowRule = rules.find((r) => r.action.type === "allow");
    expect(blockRule).toBeDefined();
    expect(allowRule).toBeDefined();
    expect(blockRule!.condition.urlFilter).toBe("youtube.com");
    expect(allowRule!.condition.urlFilter).toBe("youtube.com/watch");
  });

  // Test 3: Allow rule has strictly higher priority than block rule
  it("allow rule has priority 2, block rule has priority 1", () => {
    const rules = buildDNRRules([
      {
        pattern: "youtube.com",
        action: "block",
        exceptions: [{ pattern: "youtube.com/watch" }],
      },
    ]);
    const blockRule = rules.find((r) => r.action.type === "block");
    const allowRule = rules.find((r) => r.action.type === "allow");
    expect(blockRule!.priority).toBe(1);
    expect(allowRule!.priority).toBe(2);
    expect(allowRule!.priority).toBeGreaterThan(blockRule!.priority);
  });

  // Test 4: Rule IDs are unique positive integers
  it("rule IDs are unique positive integers", () => {
    const rules = buildDNRRules([
      {
        pattern: "twitter.com",
        action: "block",
        exceptions: [{ pattern: "twitter.com/home" }],
      },
      { pattern: "instagram.com", action: "block", exceptions: [] },
    ]);
    const ids = rules.map((r) => r.id);
    // All IDs are positive integers
    ids.forEach((id) => {
      expect(id).toBeGreaterThan(0);
      expect(Number.isInteger(id)).toBe(true);
    });
    // All IDs are unique
    const uniqueIds = new Set(ids);
    expect(uniqueIds.size).toBe(ids.length);
  });

  // Test 5: Empty array produces empty output
  it("empty array produces empty output", () => {
    const rules = buildDNRRules([]);
    expect(rules).toHaveLength(0);
    expect(rules).toEqual([]);
  });

  // Test 6: youtube.com/watch exception maps to urlFilter "youtube.com/watch" in the allow rule
  it("youtube.com/watch exception pattern maps to urlFilter in allow rule", () => {
    const rules = buildDNRRules([
      {
        pattern: "youtube.com",
        action: "block",
        exceptions: [{ pattern: "youtube.com/watch" }],
      },
    ]);
    const allowRule = rules.find((r) => r.action.type === "allow");
    expect(allowRule).toBeDefined();
    expect(allowRule!.condition.urlFilter).toBe("youtube.com/watch");
  });

  // Test 7: Multiple domains produce correct total rule count
  it("multiple domains produce correct total rule count", () => {
    const rules = buildDNRRules([
      {
        pattern: "twitter.com",
        action: "block",
        exceptions: [{ pattern: "twitter.com/home" }],
      },
      {
        pattern: "youtube.com",
        action: "block",
        exceptions: [
          { pattern: "youtube.com/watch" },
          { pattern: "youtube.com/playlist" },
        ],
      },
      { pattern: "instagram.com", action: "block", exceptions: [] },
    ]);
    // twitter.com: 1 block + 1 allow = 2
    // youtube.com: 1 block + 2 allow = 3
    // instagram.com: 1 block + 0 allow = 1
    // total = 6
    expect(rules).toHaveLength(6);
  });
});
