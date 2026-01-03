import { describe, test, expect, beforeEach, afterEach } from "vitest";
import {
  TestContext,
  createTestContext,
  cleanupTestContext,
} from "./helpers/test-utils.js";

describe("MCP Protocol", () => {
  let context: TestContext;

  beforeEach(async () => {
    context = await createTestContext();
  });

  afterEach(async () => {
    await cleanupTestContext(context);
  });

  test("client connects and initializes successfully", async () => {
    // The MCP SDK handles initialization automatically on connect()
    // If we got here without throwing, the handshake succeeded
    expect(context.client).toBeDefined();
  });

  test("server reports correct capabilities", async () => {
    const serverInfo = context.client.getServerVersion();
    expect(serverInfo).toBeDefined();
    expect(serverInfo?.name).toBe("godot-editor");
  });

  test("server supports tools capability", async () => {
    const capabilities = context.client.getServerCapabilities();
    expect(capabilities).toBeDefined();
    expect(capabilities?.tools).toBeDefined();
  });

  test("ping request succeeds", async () => {
    const result = await context.client.ping();
    expect(result).toBeDefined();
  });
});
