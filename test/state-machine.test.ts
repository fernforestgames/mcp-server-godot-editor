import { describe, test, expect, beforeEach, afterEach } from "vitest";
import {
  TestContext,
  createTestContext,
  cleanupTestContext,
} from "./helpers/test-utils.js";

/**
 * State machine tests.
 *
 * Note: The MCP SDK handles the initialize/initialized handshake automatically
 * when connect() is called, so we can't easily test the UNINITIALIZED or
 * INITIALIZING states without bypassing the SDK.
 *
 * These tests verify behavior in the INITIALIZED state.
 */
describe("State Machine", () => {
  let context: TestContext;

  beforeEach(async () => {
    context = await createTestContext();
  });

  afterEach(async () => {
    await cleanupTestContext(context);
  });

  test("server is in initialized state after connect", async () => {
    // The SDK automatically initializes on connect
    // We can verify by making requests that require INITIALIZED state
    const result = await context.client.listTools();
    expect(result.tools).toBeDefined();
  });

  test("can make multiple requests in initialized state", async () => {
    // First request
    const tools1 = await context.client.listTools();
    expect(tools1.tools).toHaveLength(4);

    // Ping
    const ping = await context.client.ping();
    expect(ping).toBeDefined();

    // Second tools list
    const tools2 = await context.client.listTools();
    expect(tools2.tools).toHaveLength(4);
  });

  test("can call tools after initialization", async () => {
    // Verify we can call tools - this requires INITIALIZED state
    const result = await context.client.callTool({
      name: "stop_playing_scene",
      arguments: {},
    });
    expect(result.content).toBeDefined();
  });
});
