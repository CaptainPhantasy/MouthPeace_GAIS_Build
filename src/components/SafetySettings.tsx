/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from "react";
import { 
  ShieldAlert, 
  Settings, 
  Sliders, 
  Layers, 
  TrendingUp, 
  HelpCircle, 
  Flame, 
  AlertOctagon, 
  Info,
  CheckCircle,
  Eye,
  ShieldAlert as ActiveIcon
} from "lucide-react";
import { RuntimeHeartbeat } from "../types";

interface SSProps {
  onInjectSensor: (id: string, type: "drift" | "lie", isL0Shadow: boolean) => void;
  heartbeats: Record<string, RuntimeHeartbeat>;
}

export function SafetySettings({ onInjectSensor, heartbeats }: SSProps) {
  const [selectedAgentId, setSelectedAgentId] = useState<string>("agent-alpha");
  const [goalGuardLevel, setGoalGuardLevel] = useState<number>(0); // L0-L3
  const [verifierLevel, setVerifierLevel] = useState<number>(0); // 0-3
  const [testInL0Shadow, setTestInL0Shadow] = useState<boolean>(true);

  const activeIds = Object.keys(heartbeats);

  // Trust ladder descriptions
  const ggLadder = [
    { label: "L0 Shadow", desc: "Logs deviations only, never alerts cockpit channels or interrupts runs. Fails open.", badge: "Default (Fails-Open)" },
    { label: "L1 Suggest", desc: "Inserts non-blocking guidance annotations inside the model prompt history context.", badge: "Passive" },
    { label: "L2 Ask", desc: "Halts run when severe drift detected, requesting authoritative operator review decision.", badge: "Human-In-The-Loop" },
    { label: "L3 Auto-Correct", desc: "Automatically aborts or replaces drifted tokens on outbound API streams instantly.", badge: "Self-Healing" }
  ];

  const verifierLadder = [
    { label: "Shadow Mode", desc: "Audits logs retrospectively. Logs claim assertions silently without interrupting channels.", badge: "Default" },
    { label: "Suggest Mode", desc: "Injects assertion repair recommendations inside next agent turn prompts.", badge: "Passive" },
    { label: "Ask Mode", desc: "Enforces reality checks. Trips channel lights during assertion discrepancies, pausing loop.", badge: "Interruption Active" },
    { label: "Auto-Correct", desc: "Automatically fails/bypasses deceitful claims with error context feeds directly.", badge: "Autonomous Enforce" }
  ];

  // PEBKAC 25 Modules catalog
  const pebkacModules = [
    { layer: "L1: Contract Compile", module: "Task breakdown metrics, evidence specification bounds, turn budgeting" },
    { layer: "L2: Evidence Enforce", module: "Tool feedback scanner, ceremonial claim auditing, validation schemas" },
    { layer: "L3: Safety Checks", module: "L3 Secrets (7 patterns), L3 Git (10 branch patterns), Circuit breaker, Rate limiter (50/turn), System output buffers (50KB cap), Repetition scanner, Escalation alerts" },
    { layer: "L4: Compact Recovery", module: "Checkpoint restoration, session indexing, compacting validations" }
  ];

  return (
    <div className="space-y-6">
      
      {/* Upper header section */}
      <div className="bg-[#181a26]/40 p-4 rounded-xl border border-white/5 backdrop-blur-md">
        <h2 className="text-lg font-bold tracking-tight text-white flex items-center space-x-2">
          <Settings className="w-5 h-5 text-teal-300" />
          <span>MouthPeace Cockpit Virtual Safety Guard Settings</span>
        </h2>
        <p className="text-xs text-slate-400 mt-1">
          Configure safety parameters, manage algorithmic trust ladders, and inspect PEBKAC/PEBKACOMP rule matrices. Use the sandbox testing tool to verify shadow checking transitions.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* LEFT TWO COLUMNS: TRUST LADDER CONTROLS */}
        <div className="lg:col-span-2 space-y-6">
          
          {/* 1. GOAL GUARD L0-L1-L2-L3 TRUST LADDER SLIDER */}
          <div className="bg-[#181a26]/40 rounded-xl border border-white/10 p-4 space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold font-mono text-slate-400 uppercase tracking-widest flex items-center space-x-1.5 select-none">
                <Sliders className="w-4 h-4 text-teal-300" />
                <span>GOAL GUARD INTENT DRIFT LADDER</span>
              </h3>
              <span className="px-2 py-0.5 rounded text-[9.5px] bg-indigo-950 border border-indigo-700/80 text-indigo-300 font-mono font-bold">
                ACTIVE MODE: {ggLadder[goalGuardLevel].label.toUpperCase()}
              </span>
            </div>

            <p className="text-[11px] text-slate-500 leading-normal">
              Goal Guard is a prospective intent sensor, monitoring active tool parameter trajectories to catch malicious shortcuts or extreme target direction drift.
            </p>

            <div className="space-y-4 pt-2">
              {/* Slider track input */}
              <input 
                type="range" 
                min="0" 
                max="3" 
                value={goalGuardLevel} 
                onChange={(e) => setGoalGuardLevel(Number(e.target.value))}
                className="w-full h-1.5 bg-slate-950 rounded-lg appearance-none cursor-pointer accent-teal-400" 
              />
              
              {/* Ladder visual grid step */}
              <div className="grid grid-cols-4 gap-2">
                {ggLadder.map((step, idx) => (
                  <div 
                    key={idx}
                    onClick={() => setGoalGuardLevel(idx)}
                    className={`p-2 rounded-lg border text-left cursor-pointer transition select-none ${
                      goalGuardLevel === idx 
                        ? "bg-teal-950/20 border-teal-500 shadow-md" 
                        : "bg-slate-950/40 border-slate-900 opacity-60 hover:opacity-100"
                    }`}
                  >
                    <span className="text-[10px] uppercase font-mono font-black text-slate-200 block">{step.label}</span>
                    <span className="text-[8px] font-bold text-teal-400 font-mono uppercase tracking-wide block mt-0.5">{step.badge}</span>
                  </div>
                ))}
              </div>

              {/* Selection explanation details */}
              <div className="p-3 bg-slate-950/60 rounded-md border border-slate-900 flex items-start space-x-2 text-[11px] text-slate-400 leading-relaxed">
                <Info className="w-4 h-4 text-teal-400 shrink-0 mt-0.5" />
                <div>
                  <span className="font-bold text-slate-300">Target Behavior Description:</span>
                  <p>{ggLadder[goalGuardLevel].desc}</p>
                </div>
              </div>
            </div>
          </div>

          {/* 2. VERIFIER RETROSPECTIVE CHECKER LADDER */}
          <div className="bg-[#181a26]/40 rounded-xl border border-white/10 p-4 space-y-4">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold font-mono text-slate-400 uppercase tracking-widest flex items-center space-x-1.5 select-none">
                <ShieldAlert className="w-4 h-4 text-blue-300" />
                <span>INTEGRITY CHECKER VERIFIER LADDER</span>
              </h3>
              <span className="px-2 py-0.5 rounded text-[9.5px] bg-indigo-950 border border-indigo-700/80 text-indigo-300 font-mono font-bold">
                ACTIVE MODE: {verifierLadder[verifierLevel].label.toUpperCase()}
              </span>
            </div>

            <p className="text-[11px] text-slate-500 leading-normal">
              Verifier is a retrospective sensor, running clean dry-run environments to check assertions, claim accuracy and mock integrity reports before task submissions.
            </p>

            <div className="space-y-4 pt-2">
              {/* Slider track input */}
              <input 
                type="range" 
                min="0" 
                max="3" 
                value={verifierLevel} 
                onChange={(e) => setVerifierLevel(Number(e.target.value))}
                className="w-full h-1.5 bg-slate-950 rounded-lg appearance-none cursor-pointer accent-blue-400" 
              />
              
              {/* Ladder visual grid step */}
              <div className="grid grid-cols-4 gap-2">
                {verifierLadder.map((step, idx) => (
                  <div 
                    key={idx}
                    onClick={() => setVerifierLevel(idx)}
                    className={`p-2 rounded-lg border text-left cursor-pointer transition select-none ${
                      verifierLevel === idx 
                        ? "bg-blue-950/20 border-blue-500 shadow-md" 
                        : "bg-slate-950/40 border-slate-900 opacity-60 hover:opacity-100"
                    }`}
                  >
                    <span className="text-[10px] uppercase font-mono font-black text-slate-200 block">{step.label}</span>
                    <span className="text-[8px] font-bold text-blue-400 font-mono uppercase tracking-wide block mt-0.5">{step.badge}</span>
                  </div>
                ))}
              </div>

              {/* Selection explanation details */}
              <div className="p-3 bg-slate-950/60 rounded-md border border-slate-900 flex items-start space-x-2 text-[11px] text-slate-400 leading-relaxed">
                <Info className="w-4 h-4 text-blue-400 shrink-0 mt-0.5" />
                <div>
                  <span className="font-bold text-slate-300">Target Behavior Description:</span>
                  <p>{verifierLadder[verifierLevel].desc}</p>
                </div>
              </div>
            </div>
          </div>

        </div>

        {/* RIGHT COLUMN: PEN-TEST PENETRATION INTEGRITY DOCK */}
        <div className="bg-[#181a26]/40 rounded-xl border border-white/10 p-4 space-y-5 flex flex-col justify-between">
          
          <div className="space-y-4">
            <div>
              <h3 className="text-xs font-bold font-mono text-slate-400 uppercase tracking-widest flex items-center space-x-1.5 select-none">
                <Flame className="w-4 h-4 text-rose-400" />
                <span>SENSOR SANDBOX PEN-TESTER</span>
              </h3>
              <p className="text-[11px] text-slate-500 mt-0.5 font-medium leading-normal">
                Command a simulated agent drift vector or deceit claim, then observe the exact telemetry response.
              </p>
            </div>

            {/* Config options */}
            <div className="space-y-3.5 pt-1.5">
              
              {/* Target transceiver drop down */}
              <div className="space-y-1.5">
                <label className="text-[9px] uppercase font-bold text-slate-500 font-mono block">Target Transceiver Device:</label>
                <select 
                  value={selectedAgentId} 
                  onChange={(e) => setSelectedAgentId(e.target.value)}
                  className="w-full p-2 rounded-lg bg-slate-950/70 border border-slate-800 text-xs text-slate-100 font-mono outline-none"
                >
                  {activeIds.map((id) => (
                    <option key={id} value={id}>
                      {id.replace("agent-", "MouthPeace-0").toUpperCase()}
                    </option>
                  ))}
                </select>
              </div>

              {/* Toggle switch between Shadow and Active Interruptions */}
              <div className="space-y-2 p-2.5 bg-slate-950/65 rounded-lg border border-slate-900">
                <span className="text-[9.5px] uppercase font-bold text-slate-500 font-mono block">Select Testing Mode:</span>
                
                <div className="flex items-center space-x-4 text-xs font-sans">
                  <label className="flex items-center space-x-1.5 cursor-pointer text-slate-300 hover:text-white">
                    <input 
                      type="radio" 
                      checked={testInL0Shadow} 
                      onChange={() => setTestInL0Shadow(true)}
                      className="accent-teal-400"
                    />
                    <span>L0 Shadow (Logs Only)</span>
                  </label>

                  <label className="flex items-center space-x-1.5 cursor-pointer text-slate-300 hover:text-white">
                    <input 
                      type="radio" 
                      checked={!testInL0Shadow} 
                      onChange={() => setTestInL0Shadow(false)}
                      className="accent-rose-500"
                    />
                    <span className="text-rose-400 font-semibold">Active Trip Lights</span>
                  </label>
                </div>

                <p className="text-[9.5px] text-slate-500 mt-1 leading-normal leading-relaxed">
                  {testInL0Shadow 
                    ? "Shadow checks verify code without interrupting. Check details inside 'Shadow Alerts Log' tab under Session Console." 
                    : "Active mode flashes transceivers red and flags alert reasons. Human decision required."}
                </p>
              </div>

              {/* Big testing buttons */}
              <div className="space-y-2 pt-1 text-xs font-bold leading-none">
                
                <button
                  onClick={() => onInjectSensor(selectedAgentId, "drift", testInL0Shadow)}
                  className="w-full p-2.5 rounded bg-slate-900 text-slate-200 border border-slate-800 hover:border-teal-500 hover:text-white transition flex items-center space-x-2"
                >
                  <Eye className="w-4 h-4 text-teal-400 shrink-0" />
                  <div className="text-left leading-normal">
                    <span className="block font-bold">Inject Goal Intent Drift</span>
                    <span className="text-[9px] text-slate-500 font-mono font-medium block">Test prospective vector check</span>
                  </div>
                </button>

                <button
                  onClick={() => onInjectSensor(selectedAgentId, "lie", testInL0Shadow)}
                  className="w-full p-2.5 rounded bg-slate-900 text-slate-200 border border-slate-800 hover:border-blue-500 hover:text-white transition flex items-center space-x-2"
                >
                  <Eye className="w-4 h-4 text-blue-400 shrink-0" />
                  <div className="text-left leading-normal">
                    <span className="block font-bold">Inject Assertion Lie</span>
                    <span className="text-[9px] text-slate-500 font-mono font-medium block">Test retrospective completion checks</span>
                  </div>
                </button>

              </div>

            </div>

          </div>

          <div className="p-3 bg-slate-950/40 rounded-lg border border-slate-850 text-[10px] text-slate-500 font-mono mt-4 leading-normal leading-relaxed">
            <span className="text-[9px] text-slate-400 uppercase font-bold block mb-1">Rule Rule Matrix status:</span>
            All 25 PEBKAC protection slots are active. Guard filters compiled into verified Bun harness events, winning execution short-circuits.
          </div>

        </div>

      </div>

      {/* MATRIX TABLE OF PEBKAC INTERNALS */}
      <div className="bg-[#181a26]/40 rounded-xl border border-white/5 p-4 space-y-4">
        <h3 className="text-xs font-bold font-mono text-slate-400 uppercase tracking-widest flex items-center space-x-1.5 select-none">
          <Layers className="w-4 h-4 text-slate-300" />
          <span>PEBKAC SECURE LAYERS INTERNAL SPECIFICATION MATRIX</span>
        </h3>

        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 text-xs">
          {pebkacModules.map((item, idx) => (
            <div key={idx} className="p-3 rounded-lg bg-slate-950/50 border border-slate-850/60 text-slate-300 space-y-1.5">
              <h4 className="font-bold text-indigo-300 tracking-wide">{item.layer}</h4>
              <p className="text-[11px] text-slate-400 leading-relaxed font-sans">{item.module}</p>
            </div>
          ))}
        </div>
      </div>

    </div>
  );
}
