import { describe, test, expect, beforeEach, afterEach } from "vitest";
import {
  TestContext,
  createTestContext,
  cleanupTestContext,
  sleep,
} from "./helpers/test-utils.js";

// These tests require a display - the editor spawns a non-headless game subprocess
// Skip in CI environments
const isCI = process.env.CI === "true";

describe.skipIf(isCI)("take_screenshot", () => {
  let context: TestContext;

  beforeEach(async () => {
    context = await createTestContext();
  });

  afterEach(async () => {
    // Ensure scene is stopped before cleanup
    try {
      await context.client.callTool({
        name: "stop_playing_scene",
        arguments: {},
      });
    } catch {
      // Ignore errors
    }
    await cleanupTestContext(context);
  });

  test("returns error when no game is running", async () => {
    const result = await context.client.callTool({
      name: "take_screenshot",
      arguments: {},
    });

    expect(result.isError).toBe(true);
    expect(result.content).toBeDefined();

    const textContent = result.content[0];
    expect(textContent.type).toBe("text");
    if (textContent.type === "text") {
      expect(textContent.text.toLowerCase()).toMatch(/no.*running|not.*running/);
    }
  });

  test("returns base64 WebP image when game is running", async () => {
    // Start the game first
    await context.client.callTool({
      name: "play_main_scene",
      arguments: {},
    });

    // Wait for the game to render at least one frame
    await sleep(1000);

    // Take screenshot
    const result = await context.client.callTool({
      name: "take_screenshot",
      arguments: {},
    });

    expect(result.isError).toBeFalsy();
    expect(result.content).toBeDefined();
    expect(result.content.length).toBeGreaterThan(0);

    const imageContent = result.content[0];
    expect(imageContent.type).toBe("image");

    if (imageContent.type === "image") {
      expect(imageContent.mimeType).toBe("image/webp");
      expect(imageContent.data).toBeDefined();
      // Check that it's valid base64
      expect(imageContent.data).toMatch(/^[A-Za-z0-9+/]+=*$/);
      // Should be non-trivial size (at least a few KB)
      expect(imageContent.data.length).toBeGreaterThan(1000);
    }
  });

  test("screenshot can be taken multiple times", async () => {
    // Start the game
    await context.client.callTool({
      name: "play_main_scene",
      arguments: {},
    });

    await sleep(500);

    // Take first screenshot
    const result1 = await context.client.callTool({
      name: "take_screenshot",
      arguments: {},
    });

    expect(result1.isError).toBeFalsy();

    await sleep(200);

    // Take second screenshot
    const result2 = await context.client.callTool({
      name: "take_screenshot",
      arguments: {},
    });

    expect(result2.isError).toBeFalsy();

    // Both should have image content
    expect(result1.content[0].type).toBe("image");
    expect(result2.content[0].type).toBe("image");
  });
});
