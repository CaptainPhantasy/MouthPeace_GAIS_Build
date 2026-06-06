/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useRef } from "react";
import { Terminal, Code, Cpu, FolderOpen, Heart, Activity } from "lucide-react";
import { RuntimeHeartbeat } from "../types";

interface SDProps {
  heartbeats: Record<string, RuntimeHeartbeat>;
  selectedId: string;
  setSelectedId: (id: string) => void;
}

export function SessionDetail({ heartbeats, selectedId, setSelectedId }: SDProps) {
  const [activeTab, setActiveTab] = useState<"terminal" | "heartbeat" | "shadow">("terminal");
  const [logs, setLogs] = useState<string[]>([]);
  const [shadowLogs, setShadowLogs] = useState<string[]>([]);
  const [currentTask, setCurrentTask] = useState("");
  const terminalEndRef = useRef<HTMLDivElement>(null);

  const activeIds = Object.keys(heartbeats);
  const selectedAgent = heartbeats[selectedId];

  // Fetch simulated live terminal outputs of target agent session from express server
  useEffect(() => {
    if (!selectedId) return;

    const fetchLogs = async () => {
      try {
        const res = await fetch(`/api/test/logs/${selectedId}`);
        const data = await res.json();
        setLogs(data.logs || []);
        setCurrentTask(data.currentTask || "");
        setShadowLogs(data.l0ShadowLogs || []);
      } catch (e) {
        console.error("Failed to sync console logs:", e);
      }
    };

    fetchLogs();
    const interval = setInterval(fetchLogs, 2000); // Poll simulator logs

    return () => clearInterval(interval);
  }, [selectedId]);

  // Scroll terminal logs to bottom on update
  useEffect(() => {
    if (activeTab === "terminal" && terminalEndRef.current) {
      terminalEndRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, [logs, activeTab]);

  return (
    <div className="space-y-6">
      
      {/* Upper selector workspace */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-[#181a26]/40 p-4 rounded-xl border border-white/5 backdrop-blur-md">
        <div className="flex items-center space-x-2.5">
          <Terminal className="w-5 h-5 text-blue-400" />
          <h2 className="text-base font-bold tracking-tight text-white font-sans">
            Diagnostic Forensics Terminal & Schema Auditor
          </h2>
        </div>

        <div className="flex items-center space-x-2">
          <span className="text-[10px] font-bold text-slate-400 font-mono">NODE SWITCH:</span>
          <div className="flex bg-slate-950/70 p-1 rounded-lg border border-slate-800 space-x-1">
            {activeIds.map((id) => (
              <button
                key={id}
                onClick={() => setSelectedId(id)}
                className={`px-2 py-1 rounded text-[10.5px] font-mono leading-none transition ${
                  selectedId === id 
                    ? "bg-blue-600 text-white font-bold" 
                    : "text-slate-450 hover:text-slate-200 hover:bg-white/5"
                }`}
              >
                {id.replace("agent-", "CH").toUpperCase()}
              </button>
            ))}
          </div>
        </div>
      </div>

      {selectedAgent ? (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          
          {/* LEFT METADATA SUMMARY BAR */}
          <div className="bg-[#181a26]/40 rounded-xl border border-white/10 p-4 space-y-4 text-xs">
            <h3 className="text-xs font-bold font-mono text-slate-400 uppercase tracking-wider flex items-center space-x-1.5 border-b border-white/5 pb-2">
              <Cpu className="w-4 h-4 text-blue-400" />
              <span>TELEMETRY METRICS</span>
            </h3>

            <div className="space-y-3.5">
              <div className="space-y-1">
                <span className="text-[10px] text-slate-500 uppercase font-mono font-semibold">Instance Identifier:</span>
                <p className="text-slate-200 font-mono font-bold break-all bg-slate-950/60 p-2 rounded border border-slate-900 select-all">
                  {selectedAgent.instanceId}
                </p>
              </div>

              <div className="space-y-1">
                <span className="text-[10px] text-slate-500 uppercase font-mono font-semibold">CWD Sandbox Path:</span>
                <p className="text-slate-350 font-mono bg-slate-950/60 p-2 rounded border border-slate-900 flex items-center space-x-1.5 leading-snug">
                  <FolderOpen className="w-4 h-4 text-blue-400 shrink-0" />
                  <span className="truncate select-all">{selectedAgent.cwd}</span>
                </p>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div className="bg-slate-950/40 p-2.5 rounded border border-white/5">
                  <span className="text-[9.5px] text-slate-500 font-mono uppercase block">Turn Code:</span>
                  <span className="font-mono text-base font-bold text-slate-100 tabular-nums">{selectedAgent.counters.turns}</span>
                </div>
                <div className="bg-slate-950/40 p-2.5 rounded border border-white/5">
                  <span className="text-[9.5px] text-slate-500 font-mono uppercase block">Tool Invocations:</span>
                  <span className="font-mono text-base font-bold text-slate-100 tabular-nums">{selectedAgent.counters.toolCalls}</span>
                </div>
                <div className="bg-slate-950/40 p-2.5 rounded border border-white/5">
                  <span className="text-[9.5px] text-slate-500 font-mono uppercase block">Tokens Out:</span>
                  <span className="font-mono text-xs font-bold text-slate-100 tabular-nums">{selectedAgent.counters.outputTokens.toLocaleString()}</span>
                </div>
                <div className="bg-slate-950/40 p-2.5 rounded border border-white/5">
                  <span className="text-[9.5px] text-slate-500 font-mono uppercase block">Process SIG-Errors:</span>
                  <span className={`font-mono text-base font-bold tabular-nums ${selectedAgent.counters.errors > 2 ? "text-rose-400 animate-pulse" : "text-slate-300"}`}>
                    {selectedAgent.counters.errors}
                  </span>
                </div>
              </div>

              {selectedAgent.activeTool && (
                <div className="p-3 bg-indigo-950/20 border border-indigo-850 rounded-lg space-y-1.5 text-[11px] leading-snug">
                  <span className="text-[9px] uppercase font-mono font-bold text-indigo-300 flex items-center">
                    <Activity className="w-3.5 h-3.5 mr-1" />
                    <span>Executing Tool</span>
                  </span>
                  <div>
                    <span className="font-mono text-indigo-200 font-bold block">{selectedAgent.activeTool.name}</span>
                    <p className="text-slate-400 mt-0.5 font-mono text-[10px] break-all">{selectedAgent.activeTool.hint}</p>
                  </div>
                </div>
              )}

              <div className="p-3 bg-slate-950/60 rounded-lg border border-slate-900 border-dashed text-[11px] text-slate-400">
                <span className="text-[9px] uppercase font-mono font-semibold block text-slate-550">Active Action Task:</span>
                <p className="text-slate-300 mt-1 leading-normal font-sans text-[11.5px] font-medium italic">
                  "{currentTask}"
                </p>
              </div>

            </div>
          </div>

          {/* RIGHT COLUMN: MAIN TAB CABINETS (CONSOLE / TRUTH SOURCE) */}
          <div className="lg:col-span-2 bg-[#181a26]/40 rounded-xl border border-white/10 overflow-hidden flex flex-col h-[480px]">
            
            {/* Headers tabs */}
            <div className="bg-slate-950/65 h-10 border-b border-white/5 px-3 flex items-center justify-between text-xs font-bold font-mono">
              <div className="flex space-x-2">
                <button
                  onClick={() => setActiveTab("terminal")}
                  className={`px-3 py-1.5 rounded-md transition ${
                    activeTab === "terminal" ? "bg-white/10 text-white" : "text-slate-450 hover:text-slate-200"
                  }`}
                >
                  Terminal stdout
                </button>
                <button
                  onClick={() => setActiveTab("heartbeat")}
                  className={`px-3 py-1.5 rounded-md transition ${
                    activeTab === "heartbeat" ? "bg-white/10 text-white" : "text-slate-450 hover:text-slate-200"
                  }`}
                >
                  Raw Heartbeat JSON on Disk
                </button>
                <button
                  onClick={() => setActiveTab("shadow")}
                  className={`px-3 py-1.5 rounded-md transition relative ${
                    activeTab === "shadow" ? "bg-white/10 text-white" : "text-slate-450 hover:text-slate-200"
                  }`}
                >
                  Shadow Alerts Log
                  {shadowLogs.length > 0 && (
                    <span className="absolute -top-1 -right-1 w-2 h-2 rounded-full bg-amber-500" />
                  )}
                </button>
              </div>

              <span className="text-[10px] text-slate-500 hidden sm:inline-block">
                {activeTab === "terminal" ? "Console Simulator" : activeTab === "heartbeat" ? "File: ~/.mouthpeace/agent/runtime/*.json" : "L0 Shadow Sentinel Outputs"}
              </span>
            </div>

            {/* Cabinet views */}
            <div className="flex-1 bg-black p-4 overflow-y-auto select-text font-mono text-xs leading-relaxed text-slate-300">
              
              {activeTab === "terminal" && (
                <div className="space-y-1">
                  <div className="text-blue-400 font-bold flex items-center space-x-1.5 select-none border-b border-white/5 pb-1 mb-2">
                    <span>MouthPeace CLI - Stream telemetry initialized:</span>
                  </div>
                  {logs.map((log, idx) => (
                    <div 
                      key={idx} 
                      className={`${
                        log.includes("VIRTUAL SHIELD") ? "text-emerald-400 font-semibold" :
                        log.includes("blocked") || log.includes("❌") ? "text-rose-400 font-bold" :
                        log.includes("Human Decision") ? "text-cyan-300 font-bold" :
                        log.includes("⚠️") ? "text-amber-300" :
                        "text-slate-300"
                      }`}
                    >
                      <span className="text-slate-500 mr-2 select-none">[{new Date(selectedAgent.lastUpdate - (logs.length - idx) * 1000).toLocaleTimeString()}]</span>
                      <code>{log}</code>
                    </div>
                  ))}
                  <div ref={terminalEndRef} />
                </div>
              )}

              {activeTab === "heartbeat" && (
                <pre className="font-mono text-[10.5px] text-emerald-400 leading-tight select-all">
                  {JSON.stringify(selectedAgent, null, 2)}
                </pre>
              )}

              {activeTab === "shadow" && (
                <div className="space-y-2">
                  <div className="text-amber-400 font-bold select-none border-b border-white/5 pb-1 mb-2">
                    <span>[L0 TRUST LADDER MODE CHECKPOINTS]</span>
                  </div>
                  {shadowLogs.length === 0 ? (
                    <p className="text-slate-500 italic text-center py-10 font-sans">
                      No shadow warnings recorded. Promote goal guard/verifier parameters in Safety Settings to test detections.
                    </p>
                  ) : (
                    shadowLogs.map((log, idx) => (
                      <div key={idx} className="p-2 border border-amber-900 bg-amber-950/20 rounded text-amber-200">
                        <code>{log}</code>
                      </div>
                    ))
                  )}
                </div>
              )}

            </div>

          </div>

        </div>
      ) : (
        <div className="p-12 text-center text-slate-500">
          No agent session loaded. Click a transceiver card to trigger deep telemetry inspection.
        </div>
      )}

    </div>
  );
}
