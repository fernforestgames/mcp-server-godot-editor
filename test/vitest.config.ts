import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["**/*.test.ts"],
    testTimeout: 60000,
    hookTimeout: 30000,
    globals: true,
    // Run tests serially - each test spawns a Godot instance
    fileParallelism: false,
    sequence: {
      shuffle: false,
    },
    // Only one test at a time across all files
    pool: "forks",
    poolOptions: {
      forks: {
        singleFork: true,
      },
    },
  },
});
