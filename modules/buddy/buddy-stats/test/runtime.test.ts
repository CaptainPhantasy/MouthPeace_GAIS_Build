import { afterEach, describe, expect, test } from "bun:test";
import {
	formatDuration,
	formatNumber,
	formatPercent,
	getConfigRootDir,
	getSessionsDir,
	getStatsDbPath,
	isEnoent,
} from "../src/runtime";

const originalConfigDir = process.env.MOUTHPEACE_CONFIG_DIR;

afterEach(() => {
	if (originalConfigDir === undefined) {
		delete process.env.MOUTHPEACE_CONFIG_DIR;
	} else {
		process.env.MOUTHPEACE_CONFIG_DIR = originalConfigDir;
	}
});

describe("self-contained Buddy runtime", () => {
	test("derives all data paths from the configured root", () => {
		process.env.MOUTHPEACE_CONFIG_DIR = "/tmp/mouthpeace-test";
		expect(getConfigRootDir()).toBe("/tmp/mouthpeace-test");
		expect(getSessionsDir()).toBe("/tmp/mouthpeace-test/agent/sessions");
		expect(getStatsDbPath()).toBe("/tmp/mouthpeace-test/stats.db");
	});

	test("recognizes only filesystem missing-file errors", () => {
		expect(
			isEnoent(Object.assign(new Error("missing"), { code: "ENOENT" })),
		).toBe(true);
		expect(isEnoent(new Error("other"))).toBe(false);
	});

	test("formats dashboard values consistently", () => {
		expect(formatDuration(500)).toBe("500ms");
		expect(formatDuration(1_500)).toBe("1.5s");
		expect(formatDuration(61_000)).toBe("1m 1s");
		expect(formatNumber(1_234.5)).toBe("1,234.5");
		expect(formatPercent(0.125)).toBe("12.5%");
	});
});
