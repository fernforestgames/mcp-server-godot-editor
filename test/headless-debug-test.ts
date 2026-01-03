/**
 * Minimal test to check if headless editor can launch a headless game
 * with a working debugger connection.
 */

import { spawn } from "node:child_process";
import { resolve } from "node:path";

const GODOT_PATH = process.env.GODOT_PATH;
if (!GODOT_PATH) {
  console.error("Set GODOT_PATH environment variable");
  process.exit(1);
}

const projectPath = resolve(import.meta.dirname, "..");

console.log("Starting headless Godot editor...");
console.log(`  Godot: ${GODOT_PATH}`);
console.log(`  Project: ${projectPath}`);

const godot = spawn(GODOT_PATH, ["--headless", "--editor", "--path", projectPath], {
  stdio: ["pipe", "pipe", "pipe"],
});

let stdout = "";
let stderr = "";

godot.stdout.on("data", (data) => {
  stdout += data.toString();
  process.stdout.write(`[stdout] ${data}`);
});

godot.stderr.on("data", (data) => {
  stderr += data.toString();
  process.stderr.write(`[stderr] ${data}`);
});

// Wait for MCP server to start
await new Promise<void>((resolve) => {
  const check = () => {
    if (stderr.includes("[MCP] MCP server started")) {
      resolve();
    }
  };
  godot.stderr.on("data", check);
  setTimeout(() => resolve(), 10000); // timeout after 10s
});

console.log("\n--- MCP server started, sending initialize request ---\n");

// Send MCP initialize request
const initRequest = JSON.stringify({
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "headless-test", version: "1.0.0" },
  },
});

godot.stdin.write(initRequest + "\n");

// Wait for response
await new Promise<void>((resolve) => {
  const check = () => {
    if (stdout.includes('"id":1')) {
      resolve();
    }
  };
  godot.stdout.on("data", check);
  setTimeout(() => resolve(), 5000);
});

console.log("\n--- Received initialize response, sending initialized notification ---\n");

// Send initialized notification
const initializedNotification = JSON.stringify({
  jsonrpc: "2.0",
  method: "notifications/initialized",
});

godot.stdin.write(initializedNotification + "\n");

// Small delay
await new Promise((r) => setTimeout(r, 500));

console.log("\n--- Calling play_main_scene ---\n");

// Call play_main_scene
const playRequest = JSON.stringify({
  jsonrpc: "2.0",
  id: 2,
  method: "tools/call",
  params: {
    name: "play_main_scene",
    arguments: {},
  },
});

godot.stdin.write(playRequest + "\n");

// Wait for response (success or timeout)
console.log("Waiting for play_main_scene response (up to 10s)...");

await new Promise<void>((resolve) => {
  const check = () => {
    if (stdout.includes('"id":2')) {
      console.log("\n--- Got response for play_main_scene ---");
      resolve();
    }
  };
  godot.stdout.on("data", check);
  // Check if already received
  if (stdout.includes('"id":2')) {
    resolve();
  }
  setTimeout(() => {
    console.log("\n--- Timeout waiting for play_main_scene response ---");
    resolve();
  }, 10000);
});

// Now try to take a screenshot to verify the game is running
console.log("\n--- Calling take_screenshot to verify game is running ---\n");

const screenshotRequest = JSON.stringify({
  jsonrpc: "2.0",
  id: 3,
  method: "tools/call",
  params: {
    name: "take_screenshot",
    arguments: {},
  },
});

godot.stdin.write(screenshotRequest + "\n");

await new Promise<void>((resolve) => {
  const check = () => {
    if (stdout.includes('"id":3')) {
      console.log("\n--- Got response for take_screenshot ---");
      resolve();
    }
  };
  godot.stdout.on("data", check);
  if (stdout.includes('"id":3')) {
    resolve();
  }
  setTimeout(() => {
    console.log("\n--- Timeout waiting for take_screenshot response ---");
    resolve();
  }, 10000);
});

// Print final state
console.log("\n=== FINAL OUTPUT ===");
console.log("STDOUT:", stdout);
console.log("\n=== STDERR (last 3000 chars) ===");
console.log(stderr.slice(-3000));

// Cleanup
godot.kill();
process.exit(0);
