import * as os from "node:os";
import * as path from "node:path";

const CONFIG_ROOT_ENV = "MOUTHPEACE_CONFIG_DIR";

export function getConfigRootDir(): string {
	return process.env[CONFIG_ROOT_ENV] || path.join(os.homedir(), ".mouthpeace");
}

export function getSessionsDir(): string {
	return path.join(getConfigRootDir(), "agent", "sessions");
}

export function getStatsDbPath(): string {
	return path.join(getConfigRootDir(), "stats.db");
}

export function isEnoent(error: unknown): boolean {
	return error instanceof Error && "code" in error && error.code === "ENOENT";
}

export function formatDuration(milliseconds: number): string {
	if (milliseconds < 1_000) return `${Math.round(milliseconds)}ms`;
	if (milliseconds < 60_000) return `${(milliseconds / 1_000).toFixed(1)}s`;
	return `${Math.floor(milliseconds / 60_000)}m ${Math.round((milliseconds % 60_000) / 1_000)}s`;
}

export function formatNumber(value: number): string {
	return new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(
		value,
	);
}

export function formatPercent(value: number): string {
	return `${(value * 100).toFixed(1)}%`;
}
