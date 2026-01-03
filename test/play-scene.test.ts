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

describe.skipIf(isCI)("Scene Control", () => {
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
      // Ignore errors if scene wasn't running
    }
    await cleanupTestContext(context);
  });

  test("play_main_scene starts the game", async () => {
    const result = await context.client.callTool({
      name: "play_main_scene",
      arguments: {},
    });

    expect(result.content).toBeDefined();
    expect(result.content.length).toBeGreaterThan(0);

    const textContent = result.content[0];
    expect(textContent.type).toBe("text");
    if (textContent.type === "text") {
      expect(textContent.text.toLowerCase()).toContain("started");
    }
  });

  test("play_scene with valid path starts the scene", async () => {
    const result = await context.client.callTool({
      name: "play_scene",
      arguments: { path: "res://main.tscn" },
    });

    expect(result.content).toBeDefined();
    expect(result.content.length).toBeGreaterThan(0);

    const textContent = result.content[0];
    expect(textContent.type).toBe("text");
    if (textContent.type === "text") {
      expect(textContent.text.toLowerCase()).toContain("started");
    }
  });

  test("play_scene with invalid path returns error", async () => {
    const result = await context.client.callTool({
      name: "play_scene",
      arguments: { path: "res://nonexistent_scene.tscn" },
    });

    expect(result.isError).toBe(true);
    expect(result.content).toBeDefined();

    const textContent = result.content[0];
    expect(textContent.type).toBe("text");
    if (textContent.type === "text") {
      expect(textContent.text.toLowerCase()).toMatch(/not found|does not exist|invalid/);
    }
  });

  test("stop_playing_scene stops the running game", async () => {
    // First start a scene
    await context.client.callTool({
      name: "play_main_scene",
      arguments: {},
    });

    // Give it a moment to start
    await sleep(500);

    // Then stop it
    const result = await context.client.callTool({
      name: "stop_playing_scene",
      arguments: {},
    });

    expect(result.content).toBeDefined();
    expect(result.content.length).toBeGreaterThan(0);

    const textContent = result.content[0];
    expect(textContent.type).toBe("text");
    if (textContent.type === "text") {
      expect(textContent.text.toLowerCase()).toContain("stop");
    }
  });

  test("stop_playing_scene when no game is running", async () => {
    const result = await context.client.callTool({
      name: "stop_playing_scene",
      arguments: {},
    });

    // Should either succeed (no-op) or return a message about no game running
    expect(result.content).toBeDefined();
  });
});
