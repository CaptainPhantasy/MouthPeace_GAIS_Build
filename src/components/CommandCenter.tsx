/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect } from "react";
import { 
  Radio, 
  Power, 
  Mic, 
  MicOff, 
  Terminal, 
  AlertOctagon, 
  Zap, 
  RotateCcw, 
  CheckCircle,
  HelpCircle
} from "lucide-react";
import { HubChannel, RuntimeHeartbeat, BuddyState } from "../types";
import { motion } from "motion/react";

interface CCProps {
  channels: HubChannel[];
  heartbeats: Record<string, RuntimeHeartbeat>;
  states: Record<string, BuddyState>;
  triggerEject: (id: string) => void;
  toggleFloor: (id: string) => void;
  toggleSignal: (id: string) => void;
  clearAlert: (id: string) => void;
  onSelectAgent: (id: string) => void;
}

export function CommandCenter({
  channels,
  heartbeats,
  states,
  triggerEject,
  toggleFloor,
  toggleSignal,
  clearAlert,
  onSelectAgent
}: CCProps) {
  // Track remaining cooldown times locally on the screen for high fidelity timers
  const [cooldownTime, setCooldownTime] = useState<Record<string, number>>({});

  useEffect(() => {
    const interval = setInterval(() => {
      const now = Date.now();
      const nextCooldowns: Record<string, number> = {};
      
      channels.forEach((c) => {
        if (c.ejected && c.cooldownUntil && c.cooldownUntil > now) {
          nextCooldowns[c.id] = Math.ceil((c.cooldownUntil - now) / 1000);
        }
      });
      setCooldownTime(nextCooldowns);
    }, 500);

    return () => clearInterval(interval);
  }, [channels]);

  return (
    <div className="space-y-6">
      {/* Upper header section */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-slate-900/45 p-4 rounded-xl border border-white/5 backdrop-blur-md">
        <div>
          <h2 className="text-lg font-bold tracking-tight text-white flex items-center space-x-2">
            <Radio className="w-5 h-5 text-indigo-400" />
            <span>MouthPeace Multi-Agent Hub Operator</span>
          </h2>
          <p className="text-xs text-slate-400 mt-1 max-w-2xl">
            Each physical transceiver card represents an autonomous operator channel. Assign, observe, and speech-instruct sessions. Hit the <span className="text-rose-400 font-bold">EJECT panic button</span> to instantly deploy a process-group level SIGKILL, bypassing model state layers.
          </p>
        </div>
        
        {/* Hub status readout */}
        <div className="flex items-center space-x-3 bg-slate-950/75 p-3 rounded-lg border border-slate-800 text-xs text-slate-400">
          <div className="flex flex-col items-center px-3 border-r border-slate-800">
            <span className="text-slate-500 font-mono text-[10px]">FLOOR SEMANTIC</span>
            <span className="text-emerald-400 font-bold mt-1">LIT FILTER ACTIVE</span>
          </div>
          <div className="flex flex-col items-center px-1">
            <span className="text-slate-500 font-mono text-[10px]">TRANSCEIVER RATE</span>
            <span className="text-indigo-300 font-bold mt-1">2.4 GHz</span>
          </div>
        </div>
      </div>

      {/* 5-CHANNEL GRID COCKPIT CARDS */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
        {channels.map((chan) => {
          const hb = chan.pairedInstanceId ? heartbeats[chan.pairedInstanceId] : null;
          const bState = chan.pairedInstanceId ? states[chan.pairedInstanceId] : "sleep";
          const isCooling = !!cooldownTime[chan.id];
          const hasWave = chan.hasFloor && !chan.ejected && chan.signalActive && hb && hb.status !== "shutting_down";

          return (
            <motion.div
              key={chan.id}
              animate={chan.alertPulse ? { scale: [1, 1.01, 1] } : {}}
              transition={chan.alertPulse ? { duration: 1.5, repeat: Infinity } : {}}
              className={`rounded-xl border flex flex-col justify-between transition h-[360px] relative overflow-hidden backdrop-blur-md ${
                chan.alertPulse 
                  ? "bg-rose-950/20 border-rose-600 shadow-lg shadow-rose-950/50" 
                  : chan.ejected 
                    ? "bg-stone-900/40 border-stone-800 opacity-75" 
                    : "bg-[#181a26]/40 border-slate-800 hover:border-slate-700 hover:bg-[#1a1c2a]/55"
              }`}
            >
              {/* Card top bar with ID and status dot */}
              <div className="p-3 border-b border-white/5 flex items-center justify-between">
                <div className="flex items-center space-x-2">
                  <span 
                    className="w-2.5 h-2.5 rounded-full" 
                    style={{ backgroundColor: chan.color }}
                  />
                  <span className="font-bold text-xs text-white uppercase tracking-wider">{chan.id}</span>
                </div>

                <div className="flex items-center space-x-1.5">
                  <span className={`text-[10px] font-mono font-extrabold px-1.5 py-0.5 rounded ${
                    bState === "idle" ? "bg-slate-900 text-slate-400 border border-slate-800" :
                    bState === "busy" ? "bg-indigo-950 text-indigo-300 border border-indigo-800/80 animate-pulse" :
                    bState === "attention" ? "bg-amber-950 text-amber-300 border border-amber-800/80 border-dashed animate-pulse" :
                    bState === "celebrate" ? "bg-emerald-950 text-emerald-300 border border-emerald-800/80" :
                    bState === "dizzy" ? "bg-rose-950 text-rose-300 border border-rose-800/80" :
                    "bg-slate-950 text-slate-500 border border-slate-900"
                  }`}>
                    {bState.toUpperCase()}
                  </span>
                </div>
              </div>

              {/* Channel content area */}
              <div className="p-3 flex-1 flex flex-col justify-between text-xs space-y-3">
                
                {/* Paired agent info block */}
                <div>
                  <div className="flex items-center justify-between text-[11px] text-slate-400 font-mono">
                    <span>PAIRED DEVICE</span>
                    <span>{hb?.model || "NO DEVICE"}</span>
                  </div>
                  <h3 
                    onClick={() => hb && onSelectAgent(hb.instanceId)}
                    className="font-bold text-sm text-slate-200 mt-1 cursor-pointer hover:text-indigo-300 hover:underline flex items-center space-x-1"
                  >
                    <span>{chan.name}</span>
                  </h3>
                </div>

                {/* Speech floor waveform simulator */}
                <div className="h-16 flex flex-col items-center justify-center bg-slate-950/45 rounded-lg border border-white/5 p-2 overflow-hidden text-center">
                  {hasWave ? (
                    <div className="w-full flex items-center justify-center space-x-1 px-2">
                      {/* Animated high fidelity equalizer bars */}
                      {[1, 2, 3, 4, 5, 4, 3, 2, 1, 3, 5, 2].map((val, idx) => (
                        <motion.div
                          key={idx}
                          animate={{ height: [10, val * 8, 10] }}
                          transition={{ repeat: Infinity, duration: 0.6 + idx * 0.05, ease: "easeInOut" }}
                          className="w-1 bg-[#6366f1] rounded-full"
                          style={{ height: "12px" }}
                        />
                      ))}
                    </div>
                  ) : (
                    <span className="text-[10px] uppercase font-mono tracking-wider font-semibold text-slate-500 flex flex-col items-center">
                      {chan.ejected ? (
                        <span className="text-rose-400">Process Dead</span>
                      ) : !chan.signalActive ? (
                        <span>Signal Muted</span>
                      ) : !chan.hasFloor ? (
                        <span className="flex items-center text-slate-500 space-x-1">
                          <MicOff className="w-3.5 h-3.5 mb-1 inline" />
                          <span>Floor Unlit</span>
                        </span>
                      ) : (
                        <span>Idle Standby</span>
                      )}
                    </span>
                  )}
                  {hasWave && (
                    <span className="text-[9px] uppercase font-mono tracking-wider font-bold text-indigo-300 mt-2 animate-pulse">
                      Mic listen ON
                    </span>
                  )}
                </div>

                {/* Goal description / alert exception output */}
                <div className="flex-1 flex flex-col justify-end text-[11px]">
                  {chan.ejected ? (
                    <div className="bg-rose-950/40 p-2 rounded border border-rose-900 border-dashed text-rose-300 text-[10px] space-y-1">
                      <span className="font-bold flex items-center uppercase text-[10px]">
                        <AlertOctagon className="w-3 h-3 mr-1" />
                        Kill Enforced
                      </span>
                      <p className="leading-tight">All session worktrees dismounted. Process group killed with SIGKILL.</p>
                    </div>
                  ) : chan.alertPulse ? (
                    <div className="bg-rose-900/30 p-2 rounded border border-rose-500/80 text-rose-200 text-[10px] space-y-1">
                      <span className="font-bold flex items-center uppercase text-[10px] tracking-wide text-rose-400">
                        <AlertOctagon className="w-3.5 h-3.5 mr-1 text-rose-400 animate-bounce" />
                        VIOLATION ALERT
                      </span>
                      <p className="leading-tight font-medium line-clamp-2">{chan.alertReason}</p>
                      
                      <button 
                        onClick={() => clearAlert(chan.id)}
                        className="mt-1.5 w-full flex items-center justify-center p-1 rounded bg-rose-950 border border-rose-700/80 text-[10px] text-rose-300 font-bold hover:bg-rose-900 transition"
                      >
                        <RotateCcw className="w-3 h-3 mr-1" />
                        Clear Telemetry Alert
                      </button>
                    </div>
                  ) : hb ? (
                    <div className="bg-slate-900/70 p-2 rounded border border-white/5 space-y-1 font-sans">
                      <span className="text-[10px] text-slate-400 uppercase font-mono font-semibold">Active Objective:</span>
                      <p className="text-slate-300 line-clamp-2 font-medium leading-tight">
                        {hb.jobs.find(j => j.status === "running")?.label || "Monitoring agent turn queue state..."}
                      </p>
                    </div>
                  ) : (
                    <span className="text-slate-500 italic p-1">No agent linked to transceiver.</span>
                  )}
                </div>

              </div>

              {/* Transceiver foot command buttons */}
              <div className="p-3 border-t border-white/5 bg-slate-950/30 flex items-center justify-between text-xs">
                
                {/* Lit / Floor Focus trigger */}
                <button
                  onClick={() => !chan.ejected && toggleFloor(chan.id)}
                  disabled={chan.ejected}
                  className={`p-1.5 rounded transition flex items-center space-x-1 border font-bold ${
                    chan.hasFloor
                      ? "bg-[#6366f1] text-white border-[#5a5ddc] shadow-md shadow-[#6366f1]/25"
                      : "bg-[#181c2b] text-slate-400 border-slate-800 hover:text-slate-200"
                  } ${chan.ejected ? "opacity-35 cursor-not-allowed" : ""}`}
                >
                  {chan.hasFloor ? <Mic className="w-3.5 h-3.5" /> : <MicOff className="w-3.5 h-3.5 text-slate-500" />}
                  <span>{chan.hasFloor ? "LIT" : "UNLIT"}</span>
                </button>

                {/* Signal switch */}
                <button
                  onClick={() => !chan.ejected && toggleSignal(chan.id)}
                  disabled={chan.ejected}
                  className={`p-1.5 rounded border transition flex items-center space-x-1 ${
                    chan.signalActive
                      ? "bg-teal-950/60 border-teal-800 text-teal-300"
                      : "bg-slate-950 text-slate-500 border-slate-900"
                  } ${chan.ejected ? "opacity-35 cursor-not-allowed" : ""}`}
                >
                  <Radio className="w-3.5 h-3.5" />
                  <span>{chan.signalActive ? "SIGNAL ON" : "MUTED"}</span>
                </button>

                {/* Panic seatbelt eject button */}
                <button
                  onClick={() => triggerEject(chan.id)}
                  disabled={isCooling}
                  className={`p-1.5 px-2.5 rounded font-bold border transition flex items-center space-x-1 ${
                    chan.ejected 
                      ? "bg-rose-950 text-rose-500 border-rose-900 italic cursor-not-allowed" 
                      : "bg-rose-600 hover:bg-rose-700 text-white border-rose-500 shadow-md shadow-rose-900/30 active:scale-95"
                  }`}
                >
                  <Power className="w-3.5 h-3.5 mr-0.5" />
                  <span>{isCooling ? `COOLDOWN ${cooldownTime[chan.id]}s` : chan.ejected ? "KILLED" : "EJECT"}</span>
                </button>

              </div>
            </motion.div>
          );
        })}
      </div>
    </div>
  );
}
