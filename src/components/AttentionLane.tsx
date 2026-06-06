/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React from "react";
import { 
  AlertOctagon, 
  Check, 
  X, 
  RotateCcw, 
  ShieldAlert, 
  Terminal, 
  Activity, 
  Cpu, 
  Clock, 
  Lock
} from "lucide-react";
import { RuntimeHeartbeat, SafetyCatch, BuddyState, HubChannel } from "../types";

interface ALProps {
  heartbeats: Record<string, RuntimeHeartbeat>;
  states: Record<string, BuddyState>;
  safetyCatches: SafetyCatch[];
  channels: HubChannel[];
  clearAlert: (id: string) => void;
  onResolvePrompt: (id: string, decision: "approve" | "abort") => void;
}

export function AttentionLane({
  heartbeats,
  states,
  safetyCatches,
  channels,
  clearAlert,
  onResolvePrompt
}: ALProps) {
  // Extract all agents with pending prompts
  const activePromptAgents = Object.values(heartbeats).filter(hb => hb.pendingPrompt);

  return (
    <div className="space-y-6">
      
      {/* Upper header section */}
      <div className="bg-slate-905/45 p-4 rounded-xl border border-white/5 backdrop-blur-md">
        <h2 className="text-lg font-bold tracking-tight text-white flex items-center space-x-2">
          <AlertOctagon className="w-5 h-5 text-amber-500 animate-pulse" />
          <span>Attention Lane — Security & Prompt Checkpoints</span>
        </h2>
        <p className="text-xs text-slate-400 mt-1">
          When autonomous agents encounter critical checkpoints (permissions checks, PEBKAC blocks, or drift anomalies), execution pauses. Real-time forensic diagnostic metrics are compiled below. Review and provide authoritative human decisions here.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        
        {/* LEFT COLUMN: ACTIVE INTERACTIVE DECISION PROMPTS */}
        <div className="space-y-4 bg-[#181a26]/40 rounded-xl border border-white/5 p-4">
          <h3 className="text-xs font-bold font-mono text-slate-400 uppercase tracking-wider flex items-center justify-between">
            <span>PENDING TASK CHECKS (HUMAN-IN-THE-LOOP)</span>
            <span className="text-[10px] px-2 py-0.5 rounded bg-slate-900 text-amber-300 border border-slate-800 font-bold">
              {activePromptAgents.length} AWAITING DECISION
            </span>
          </h3>

          {activePromptAgents.length === 0 ? (
            <div className="p-12 text-center rounded-lg bg-slate-950/20 border border-slate-905 flex flex-col items-center justify-center space-y-3">
              <Check className="w-8 h-8 text-emerald-400" />
              <span className="text-sm font-semibold text-slate-300">All agent queues clear</span>
              <p className="text-xs text-slate-500 max-w-sm">No active processes are paused at checkpoints waiting for manual tool authorization.</p>
            </div>
          ) : (
            <div className="space-y-4">
              {activePromptAgents.map((agent) => {
                const prompt = agent.pendingPrompt!;
                return (
                  <div 
                    key={agent.instanceId} 
                    className="p-4 rounded-lg bg-[#212330]/85 border border-amber-600/50 shadow-lg shadow-amber-950/20 space-y-3 animate-fade-in"
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center space-x-2">
                        <span className="w-2.5 h-2.5 rounded-full bg-amber-400 animate-ping" />
                        <span className="text-xs font-bold text-slate-200">
                          {agent.instanceId.replace("agent-", "MouthPeace-0").toUpperCase()}
                        </span>
                        <span className="text-[9px] uppercase font-mono px-1.5 py-0.5 bg-slate-900 border border-slate-800 rounded font-semibold text-amber-300">
                          {prompt.tool} PAUSE
                        </span>
                      </div>
                      
                      <div className="flex items-center space-x-1 text-[10px] text-slate-500 font-mono">
                        <Clock className="w-3.5 h-3.5" />
                        <span>Just now</span>
                      </div>
                    </div>

                    <div className="p-3 bg-slate-950/70 border border-slate-900 rounded font-mono text-[11px] leading-relaxed select-text space-y-2 text-slate-300">
                      <div className="font-bold text-amber-300 flex items-center space-x-1">
                        <span>CHECKPOINT ACTION REQUIREMENT:</span>
                      </div>
                      <p className="text-slate-200 italic">"{prompt.text || "No prompt detail available."}"</p>
                      
                      <div className="pt-2 border-t border-white/5 flex flex-col text-[10px] space-y-1 text-slate-400">
                        <span><b className="text-slate-300">Tool Target:</b> {prompt.tool}</span>
                        <span><b className="text-slate-300">Parameter Hint:</b> {prompt.hint}</span>
                      </div>
                    </div>

                    {/* Authoritative human action panel */}
                    <div className="flex items-center space-x-2.5 pt-1.5 text-xs font-bold">
                      <button
                        onClick={() => onResolvePrompt(agent.instanceId, "approve")}
                        className="flex-1 p-2 rounded bg-emerald-600 hover:bg-emerald-700 text-white shadow-md shadow-emerald-950/40 flex items-center justify-center space-x-1.5 transition active:scale-95"
                      >
                        <Check className="w-4 h-4" />
                        <span>APPROVE & RESUME ROUTE</span>
                      </button>

                      <button
                        onClick={() => onResolvePrompt(agent.instanceId, "abort")}
                        className="flex-1 p-2 rounded bg-rose-600 hover:bg-rose-700 text-white shadow-md shadow-rose-950/40 flex items-center justify-center space-x-1.5 transition active:scale-95"
                      >
                        <X className="w-4 h-4" />
                        <span>ABORT CHECKPOINT</span>
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* RIGHT COLUMN: FORENSIC EXCEPTION LEDGER LIST */}
        <div className="space-y-4 bg-[#181a26]/40 rounded-xl border border-white/5 p-4">
          <h3 className="text-xs font-bold font-mono text-slate-400 uppercase tracking-wider flex items-center justify-between">
            <span>HISTORIC SECURITY & SENSOR EXCEPTION CATCHES</span>
            <span className="text-[10px] px-2 py-0.5 rounded bg-slate-900 text-rose-400 border border-slate-800 font-bold">
              {safetyCatches.length} EVENTS RECORDED
            </span>
          </h3>

          {safetyCatches.length === 0 ? (
            <div className="p-12 text-center rounded-lg bg-slate-950/20 border border-slate-905 text-slate-500">
              No safety exceptions recorded in local telemetry archives.
            </div>
          ) : (
            <div className="space-y-4.5 max-h-[500px] overflow-y-auto pr-1">
              {safetyCatches.map((item) => {
                const channel = channels.find(c => c.pairedInstanceId === item.instanceId);
                const isTripped = channel?.alertPulse;

                return (
                  <div 
                    key={item.id} 
                    className={`p-3 rounded-lg border text-xs space-y-2 bg-slate-950/40 ${
                      isTripped 
                        ? "border-rose-600/60 shadow-md shadow-rose-950/25" 
                        : "border-slate-850"
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center space-x-2">
                        {/* Type tag icon selection */}
                        <span className={`px-1.5 py-0.2 rounded font-mono text-[9.5px] font-bold ${
                          item.type === "PEBKAC" ? "bg-red-950/60 text-red-300 border border-red-900" :
                          item.type === "SENTINEL" ? "bg-amber-950/60 text-amber-300 border border-amber-900" :
                          item.type === "VERIFIER" ? "bg-cyan-950/60 text-cyan-300 border border-cyan-800" :
                          "bg-stone-900 text-slate-400 border border-stone-850"
                        }`}>
                          {item.type} {item.ruleId ? `[${item.ruleId}]` : ""}
                        </span>
                        
                        <span className="font-semibold text-slate-205">
                          {item.instanceId.replace("agent-", "MouthPeace-0").toUpperCase()}
                        </span>
                      </div>

                      <span className="text-[10px] font-mono text-slate-500">
                        {new Date(item.timestamp).toLocaleTimeString()}
                      </span>
                    </div>

                    <div className="space-y-1">
                      <h4 className="font-bold text-slate-200 text-xs flex items-center space-x-1">
                        <AlertOctagon className="w-3.5 h-3.5 text-rose-500 inline mr-1" />
                        <span>{item.message}</span>
                      </h4>
                      <p className="text-slate-400 text-[11px] leading-relaxed">{item.details}</p>
                    </div>

                    {item.evidence && (
                      <div className="p-2 rounded bg-slate-950 border border-slate-900 font-mono text-[9.5px] text-slate-400 leading-tight select-text overflow-x-auto">
                        <span className="text-rose-400 font-bold block mb-1">AGGREGATED FORENSIC TELEMETRY EVIDENCE:</span>
                        <code>{item.evidence}</code>
                      </div>
                    )}

                    {isTripped && (
                      <div className="flex items-center justify-between pt-1 text-[11px] border-t border-white/5">
                        <span className="text-rose-400 animate-pulse font-bold uppercase text-[9.5px]">Active Intercept Active</span>
                        <button
                          onClick={() => clearAlert(channel!.id)}
                          className="p-1 px-2 text-[10px] font-bold rounded bg-slate-900 hover:bg-slate-800 text-slate-300 border border-slate-800 flex items-center space-x-1"
                        >
                          <RotateCcw className="w-3 h-3" />
                          <span>Reset Channel Flag</span>
                        </button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>

      </div>

    </div>
  );
}
