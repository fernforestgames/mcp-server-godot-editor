import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { McpError, ErrorCode } from "@modelcontextprotocol/sdk/types.js";
import {
  TestContext,
  createTestContext,
  cleanupTestContext,
} from "./helpers/test-utils.js";

describe("Error Handling", () => {
  let context: TestContext;

  beforeEach(async () => {
    context = await createTestContext();
  });

  afterEach(async () => {
    await cleanupTestContext(context);
  });

  test("unknown method returns method not found error", async () => {
    try {
      await context.client.request(
        { method: "unknown/method", params: {} },
        { type: "object" } as any
      );
      expect.fail("Should have thrown an error");
    } catch (error) {
      expect(error).toBeInstanceOf(McpError);
      const mcpError = error as McpError;
      expect(mcpError.code).toBe(ErrorCode.MethodNotFound);
    }
  });

  test("tools/call with unknown tool throws invalid params error", async () => {
    // The server returns a JSON-RPC error for unknown tools
    try {
      await context.client.callTool({
        name: "nonexistent_tool",
        arguments: {},
      });
      expect.fail("Should have thrown an error");
    } catch (error) {
      expect(error).toBeInstanceOf(McpError);
      const mcpError = error as McpError;
      expect(mcpError.code).toBe(ErrorCode.InvalidParams);
      expect(mcpError.message).toContain("Unknown tool");
    }
  });

  test("tools/call with missing required parameter throws error", async () => {
    // play_scene requires 'path' parameter
    try {
      await context.client.callTool({
        name: "play_scene",
        arguments: {},
      });
      expect.fail("Should have thrown an error");
    } catch (error) {
      expect(error).toBeInstanceOf(McpError);
      const mcpError = error as McpError;
      expect(mcpError.code).toBe(ErrorCode.InvalidParams);
      expect(mcpError.message).toContain("path");
    }
  });
});
