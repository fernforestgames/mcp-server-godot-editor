import { resolve } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

export interface TestContext {
  client: Client;
  transport: StdioClientTransport;
}

export function getGodotPath(): string {
  const godotPath = process.env.GODOT_PATH;
  if (!godotPath) {
    throw new Error(
      "GODOT_PATH environment variable is not set. " +
        "Set it to the path of your Godot executable."
    );
  }
  return godotPath;
}

export async function createTestContext(): Promise<TestContext> {
  const godotPath = getGodotPath();
  const projectPath = resolve(import.meta.dirname, "../..");

  const transport = new StdioClientTransport({
    command: godotPath,
    args: ["--headless", "--editor", "--path", projectPath],
  });

  const client = new Client({
    name: "test-client",
    version: "1.0.0",
  });

  await client.connect(transport);

  return { client, transport };
}

export async function cleanupTestContext(context: TestContext): Promise<void> {
  try {
    await context.client.close();
  } catch {
    // Ignore close errors
  }
  try {
    await context.transport.close();
  } catch {
    // Ignore close errors
  }
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
