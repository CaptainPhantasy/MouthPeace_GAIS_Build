/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React from "react";
import { Layers, Play, CheckCircle, Flame, Clock } from "lucide-react";
import { RuntimeHeartbeat, BuddyState } from "../types";

interface JVProps {
  heartbeats: Record<string, RuntimeHeartbeat>;
  states: Record<string, BuddyState>;
}

export function JobsView({ heartbeats, states }: JVProps) {
  const activeIds = Object.keys(heartbeats);
  
  // Aggregate all jobs from all active channels
  const allJobs = activeIds.flatMap((id) => {
    const hb = heartbeats[id];
    return hb.jobs.map((job) => ({
      ...job,
      instanceId: id,
      agentState: states[id]
    }));
  });

  return (
    <div className="space-y-6">
      
      {/* Upper header section */}
      <div className="bg-slate-905/45 p-4 rounded-xl border border-white/5 backdrop-blur-md">
        <h2 className="text-lg font-bold tracking-tight text-white flex items-center space-x-2">
          <Layers className="w-5 h-5 text-emerald-400" />
          <span>Jobs View — Worktree Task Scheduler</span>
        </h2>
        <p className="text-xs text-slate-400 mt-1">
          Displays current isolated worktree environment executions, active test runners, or compilation processes. Monitor queue depths and scheduling delays to observe fleet dispatching efficiency.
        </p>
      </div>

      <div className="bg-[#181a26]/40 rounded-xl border border-white/5 p-4 space-y-4">
        <h3 className="text-xs font-bold font-mono text-slate-400 uppercase tracking-wider flex items-center justify-between">
          <span>RUNNING & COMPLETED PROCESS SCHEDULER QUEUE</span>
          <span className="text-[10px] px-2 py-0.5 rounded bg-slate-900 text-emerald-400 border border-slate-800 font-bold">
            {allJobs.length} TOTAL ACTIONS IN TELEMETRY
          </span>
        </h3>

        {allJobs.length === 0 ? (
          <div className="p-12 text-center rounded-lg bg-slate-950/20 border border-slate-905 text-slate-500">
            No active schedules running.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-xs text-left text-slate-300">
              <thead className="text-[10px] uppercase font-bold text-slate-500 border-b border-white/5 bg-slate-950/20">
                <tr>
                  <th className="p-3">Job ID</th>
                  <th className="p-3">Executing Session</th>
                  <th className="p-3">Job Type</th>
                  <th className="p-3">Action Label / Instruction</th>
                  <th className="p-3">Execution Age</th>
                  <th className="p-3 text-right">Job Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5">
                {allJobs.map((job) => (
                  <tr key={job.id} className="hover:bg-white/5 transition">
                    <td className="p-3 font-mono font-bold text-slate-400">{job.id}</td>
                    <td className="p-3 font-semibold text-slate-200">
                      <div className="flex flex-col">
                        <span>{job.instanceId.replace("agent-", "MouthPeace-0").toUpperCase()}</span>
                        <span className="text-[9px] uppercase font-mono text-slate-500">State: {job.agentState}</span>
                      </div>
                    </td>
                    <td className="p-3">
                      <span className={`px-1.5 py-0.5 rounded text-[10px] font-mono font-bold uppercase ${
                        job.type === "bash" ? "bg-amber-950 text-amber-300 border border-amber-900" : "bg-emerald-950 text-emerald-300 border border-emerald-900"
                      }`}>
                        {job.type}
                      </span>
                    </td>
                    <td className="p-3 select-text font-mono text-slate-300">
                      <code>{job.label}</code>
                    </td>
                    <td className="p-3 font-mono opacity-70">
                      {Math.floor((Date.now() - job.startTime) / 1000)}s ago
                    </td>
                    <td className="p-3 text-right">
                      <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                        job.status === "running" ? "bg-indigo-950 border border-indigo-800 text-indigo-300 animate-pulse" :
                        job.status === "completed" ? "bg-emerald-950 border border-emerald-800 text-emerald-300" :
                        "bg-red-950 border border-red-900 text-red-300"
                      }`}>
                        ● {job.status.toUpperCase()}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

    </div>
  );
}
