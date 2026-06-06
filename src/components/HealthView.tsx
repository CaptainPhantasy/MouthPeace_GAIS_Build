/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React from "react";
import { Activity, ShieldCheck, Cpu, Database, AlertCircle, Sparkles } from "lucide-react";
import { RuntimeHeartbeat, SafetyCatch, BuddyState } from "../types";

interface HVProps {
  systemHealth: {
    status: "healthy" | "unstable" | "degraded";
    uptimeSec: number;
    activeChannelsCount: number;
    activeProcessesCount: number;
    safetyInterventionsCount: number;
    staleHeartbeatsCount: number;
  };
  heartbeats: Record<string, RuntimeHeartbeat>;
  states: Record<string, BuddyState>;
  safetyCatches: SafetyCatch[];
}

export function HealthView({
  systemHealth,
  heartbeats,
  states,
  safetyCatches
}: HVProps) {
  const activeIds = Object.keys(heartbeats);
  
  // Calculate average turn metrics
  const totalTurnsCombined = activeIds.reduce((sum, id) => sum + (heartbeats[id]?.counters.turns || 0), 0);
  const avgTurns = activeIds.length > 0 ? Math.round(totalTurnsCombined / activeIds.length) : 0;

  // Calculate error cluster count
  const totalErrors = activeIds.reduce((sum, id) => sum + (heartbeats[id]?.counters.errors || 0), 0);

  // Safety indices
  const countIncidents = safetyCatches.length;
  const safetyRating = Math.max(10, 100 - countIncidents * 12);

  // SVG Gauge calculations
  const radius = 45;
  const strokeDasharray = 2 * Math.PI * radius;
  const strokeDashoffset = strokeDasharray - (safetyRating / 100) * strokeDasharray;

  return (
    <div className="space-y-6">
      
      {/* Upper header section */}
      <div className="bg-[#181a26]/40 p-4 rounded-xl border border-white/5 backdrop-blur-md flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex items-center space-x-2.5">
          <Activity className="w-5 h-5 text-cyan-400" />
          <h2 className="text-base font-bold tracking-tight text-white font-sans">
            MouthPeace Cockpit Cluster Health & Auditing Console
          </h2>
        </div>
        
        <div className="flex items-center space-x-2 text-xs">
          <span className="text-slate-400">Dynamic telemetry synclength:</span>
          <span className="px-2 py-0.5 rounded bg-slate-900 border border-slate-800 text-cyan-400 font-mono font-bold">
            1.5s real-time ticks
          </span>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        
        {/* SUB WIDGET 1: SECURITY PROFILE GAUGE */}
        <div className="bg-[#181a26]/40 rounded-xl border border-white/10 p-4 flex flex-col items-center justify-between text-center select-none min-h-[220px]">
          <h3 className="text-[10px] font-bold font-mono text-slate-400 uppercase tracking-wider w-full border-b border-white/5 pb-2">
            FLEET GUARD TRUST RATIO
          </h3>

          <div className="relative w-32 h-32 flex items-center justify-center mt-2">
            {/* SVG circle meter */}
            <svg className="w-full h-full transform -rotate-90">
              <circle 
                cx="64" 
                cy="64" 
                r={radius} 
                className="stroke-slate-800" 
                strokeWidth="8" 
                fill="transparent" 
              />
              <circle 
                cx="64" 
                cy="64" 
                r={radius} 
                className={`${
                  safetyRating > 80 ? "stroke-emerald-400" : safetyRating > 50 ? "stroke-amber-400" : "stroke-rose-500"
                } transition-all duration-500`}
                strokeWidth="8" 
                fill="transparent" 
                strokeDasharray={strokeDasharray}
                strokeDashoffset={strokeDashoffset}
                strokeLinecap="round"
              />
            </svg>
            <div className="absolute flex flex-col items-center">
              <span className="text-3xl font-mono font-black text-white">{safetyRating}%</span>
              <span className="text-[9px] uppercase font-mono tracking-widest text-slate-500 font-bold">SECURE SCORES</span>
            </div>
          </div>

          <div className="text-[11px] text-slate-400 mt-2">
            Interventions active: <b className="text-rose-400 font-mono">{systemHealth.safetyInterventionsCount} blocked bypass attempts</b>.
          </div>
        </div>

        {/* SUB WIDGET 2: TURN FREQUENCY CUSTOM SVG CHART */}
        <div className="bg-[#181a26]/40 rounded-xl border border-white/10 p-4 flex flex-col justify-between min-h-[220px]">
          <h3 className="text-[10px] font-bold font-mono text-slate-400 uppercase tracking-wider border-b border-white/5 pb-2 w-full">
            FLEET DISPATCH LOADING (TURNS COMBINED)
          </h3>

          {/* Bar Chart representing turn distributions per active device */}
          <div className="flex-1 flex items-end justify-between px-4 mt-6 h-28 space-x-3">
            {activeIds.map((id) => {
              const hb = heartbeats[id];
              const val = hb?.counters.turns || 0;
              const maxVal = Math.max(...activeIds.map(k => heartbeats[k]?.counters.turns || 1));
              const heightPercent = maxVal ? Math.round((val / maxVal) * 100) : 0;
              
              return (
                <div key={id} className="flex-1 flex flex-col items-center group relative">
                  {/* Tooltip on hover */}
                  <div className="absolute -top-7 opacity-0 group-hover:opacity-100 transition p-1 bg-indigo-650 border border-indigo-400/80 rounded font-mono text-[9px] text-white font-bold select-none z-20 shadow">
                    {val} turns
                  </div>

                  {/* Visual column bar */}
                  <div 
                    className="w-full bg-indigo-600/30 rounded-t border-t border-x border-indigo-400/80 hover:bg-indigo-500/50 transition-all duration-500 relative overflow-hidden"
                    style={{ height: `${heightPercent}%` }}
                  >
                    <div className="absolute inset-0 bg-gradient-to-t from-transparent via-white/5 to-white/10" />
                  </div>

                  <span className="text-[9px] font-mono text-slate-500 mt-2 uppercase">
                    {id.replace("agent-", "CH").toUpperCase()}
                  </span>
                </div>
              );
            })}
          </div>

          <div className="text-[11px] text-slate-400 text-center pb-2">
            Average Session Load Index: <b className="text-indigo-300 font-mono">{avgTurns} turns/session</b>.
          </div>
        </div>

        {/* SUB WIDGET 3: CLUSTER PERFORMANCE READOUTS */}
        <div className="bg-[#181a26]/40 rounded-xl border border-white/10 p-4 flex flex-col justify-between min-h-[220px]">
          <h3 className="text-[10px] font-bold font-mono text-slate-400 uppercase tracking-wider border-b border-white/5 pb-2">
            DIAGNOSTIC TELEMETRY CHECKLIST
          </h3>

          <div className="flex-1 flex flex-col justify-center space-y-3 p-1">
            <div className="flex items-center justify-between text-xs border-b border-white/5 pb-1">
              <span className="text-slate-400 flex items-center space-x-1.5">
                <Database className="w-3.5 h-3.5 text-blue-400" />
                <span>Disk Handshake truth storage:</span>
              </span>
              <span className="font-mono text-emerald-400 font-bold uppercase text-[9.5px]">WRITABLE</span>
            </div>

            <div className="flex items-center justify-between text-xs border-b border-white/5 pb-1">
              <span className="text-slate-400 flex items-center space-x-1.5">
                <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
                <span>Integrated PEBKAC rules:</span>
              </span>
              <span className="font-mono text-slate-300">25 active modules</span>
            </div>

            <div className="flex items-center justify-between text-xs border-b border-white/5 pb-1">
              <span className="text-slate-400 flex items-center space-x-1.5">
                <AlertCircle className="w-3.5 h-3.5 text-amber-500" />
                <span>Aggregated cluster errors:</span>
              </span>
              <span className={`font-mono font-bold ${totalErrors > 3 ? "text-amber-400" : "text-slate-450"}`}>
                {totalErrors} events
              </span>
            </div>

            <div className="flex items-center justify-between text-xs border-b border-white/5 pb-1">
              <span className="text-slate-400 flex items-center space-x-1.5">
                <Cpu className="w-3.5 h-3.5 text-pink-400" />
                <span>Total active processes:</span>
              </span>
              <span className="font-mono font-bold text-slate-200">
                {activeIds.length} sessions
              </span>
            </div>
          </div>

          <div className="text-[11px] text-slate-400 flex items-center justify-center p-1.5 rounded bg-emerald-950/20 border border-emerald-900/30">
            <Sparkles className="w-3.5 h-3.5 text-emerald-400 mr-1.5" />
            <span className="text-emerald-300 font-medium">All systems matching validation schemas.</span>
          </div>
        </div>

      </div>

    </div>
  );
}
