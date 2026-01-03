import { describe, test, expect, beforeEach, afterEach } from "vitest";
import {
  TestContext,
  createTestContext,
  cleanupTestContext,
} from "./helpers/test-utils.js";

describe("tools/list", () => {
  let context: TestContext;

  beforeEach(async () => {
    context = await createTestContext();
  });

  afterEach(async () => {
    await cleanupTestContext(context);
  });

  test("returns all available tools", async () => {
    const result = await context.client.listTools();

    expect(result.tools).toHaveLength(4);

    const toolNames = result.tools.map((t) => t.name);
    expect(toolNames).toContain("take_screenshot");
    expect(toolNames).toContain("play_main_scene");
    expect(toolNames).toContain("play_scene");
    expect(toolNames).toContain("stop_playing_scene");
  });

  test("take_screenshot has correct description", async () => {
    const result = await context.client.listTools();
    const tool = result.tools.find((t) => t.name === "take_screenshot");

    expect(tool).toBeDefined();
    expect(tool?.description).toContain("screenshot");
  });

  test("play_scene has required path parameter", async () => {
    const result = await context.client.listTools();
    const tool = result.tools.find((t) => t.name === "play_scene");

    expect(tool).toBeDefined();
    expect(tool?.inputSchema).toBeDefined();

    const schema = tool?.inputSchema as {
      properties?: Record<string, unknown>;
      required?: string[];
    };

    expect(schema.properties?.path).toBeDefined();
    expect(schema.required).toContain("path");
  });

  test("play_main_scene has no required parameters", async () => {
    const result = await context.client.listTools();
    const tool = result.tools.find((t) => t.name === "play_main_scene");

    expect(tool).toBeDefined();

    const schema = tool?.inputSchema as {
      required?: string[];
    };

    expect(schema.required ?? []).toHaveLength(0);
  });

  test("stop_playing_scene has no required parameters", async () => {
    const result = await context.client.listTools();
    const tool = result.tools.find((t) => t.name === "stop_playing_scene");

    expect(tool).toBeDefined();

    const schema = tool?.inputSchema as {
      required?: string[];
    };

    expect(schema.required ?? []).toHaveLength(0);
  });
});
