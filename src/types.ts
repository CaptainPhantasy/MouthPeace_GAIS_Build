/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

export interface RuntimeHeartbeat {
  schemaVersion: 1;
  instanceId: string;
  pid: number;
  ppid: number;
  cwd: string;
  sessionId: string;
  sessionPath?: string;
  status: "idle" | "running" | "waiting" | "degraded" | "shutting_down";
  model?: string;
  activeTurn?: { 
    startedAt: number; 
    latestText?: string;
  };
  activeTool?: { 
    id: string; 
    name: string; 
    startedAt: number; 
    hint?: string;
  };
  jobs: Array<{ 
    id: string; 
    type: "bash" | "task"; 
    status: string; 
    label: string; 
    startTime: number;
  }>;
  pendingPrompt?: { 
    id: string; 
    kind: "permission" | "ask" | "resolve"; 
    tool?: string; 
    hint?: string; 
    createdAt: number; 
    choices: string[];
    text?: string;
  };
  counters: { 
    turns: number; 
    toolCalls: number; 
    errors: number; 
    outputTokens: number;
  };
  lastUpdate: number; // local receive timestamp
}

export type BuddyState = 
  | "sleep" 
  | "idle" 
  | "busy" 
  | "attention" 
  | "celebrate" 
  | "dizzy" 
  | "heart";

export interface HubChannel {
  id: string;               // Channel 1-5 (e.g. "CH1", "CH2", "CH3", "CH4", "CH5")
  name: string;             // Human friendly name (e.g., "MouthPeace-01")
  color: string;            // hex or Tailwind color class (e.g. "indigo", "rose", "emerald", "amber", "cyan")
  pairedInstanceId?: string; // currently paired agent heartbeat ID
  hasFloor: boolean;        // Voice Floor control
  signalActive: boolean;    // Transmitting active (on/off)
  alertPulse: boolean;      // Flashing on ping (needs attention)
  alertReason?: string;     // Reason for flash (e.g., Git violation, Prompt decision wait, Goal Drift)
  ejected: boolean;         // Process group eject state
  cooldownUntil?: number;   // Timestamp till eject cooldown ends
}

export interface SafetyCatch {
  id: string;
  instanceId: string;
  timestamp: number;
  type: "PEBKAC" | "PEBKACOMP" | "SENTINEL" | "VERIFIER" | "SYSTEM_EJECT";
  severity: "info" | "warn" | "critical";
  message: string;
  details: string;
  ruleId?: string;
  evidence?: string;
}

export interface SnapshotResponse {
  channels: HubChannel[];
  heartbeats: Record<string, RuntimeHeartbeat>;
  states: Record<string, BuddyState>;
  safetyCatches: SafetyCatch[];
  systemHealth: {
    status: "healthy" | "unstable" | "degraded";
    uptimeSec: number;
    activeChannelsCount: number;
    activeProcessesCount: number;
    safetyInterventionsCount: number;
    staleHeartbeatsCount: number;
  };
}
