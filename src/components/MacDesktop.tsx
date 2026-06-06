/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useRef } from "react";
import { 
  ShieldAlert, 
  Settings, 
  Terminal, 
  Activity, 
  Volume2, 
  VolumeX, 
  Wifi, 
  ChevronRight, 
  Sliders, 
  AlertOctagon, 
  Radio, 
  Power, 
  Layers, 
  CheckCircle,
  HelpCircle,
  Cpu,
  RefreshCw,
  Zap,
  Mic,
  Sun,
  Moon
} from "lucide-react";
import { RuntimeHeartbeat, HubChannel, SafetyCatch, BuddyState, SnapshotResponse } from "../types";
import { motion, AnimatePresence } from "motion/react";
import { CommandCenter } from "./CommandCenter";
import { ProcessBoard } from "./ProcessBoard";
import { AttentionLane } from "./AttentionLane";
import { JobsView } from "./JobsView";
import { SessionDetail } from "./SessionDetail";
import { HealthView } from "./HealthView";
import { SafetySettings } from "./SafetySettings";

export default function MacDesktop() {
  const [snapshot, setSnapshot] = useState<SnapshotResponse | null>(null);
  const [time, setTime] = useState(new Date());
  const [showMenulet, setShowMenulet] = useState(false);
  const [selectedTab, setSelectedTab] = useState<string>("cockpit");
  const [theme, setTheme] = useState<"light" | "dark" | "system">("dark");
  const [broadcastMode, setBroadcastMode] = useState(false);
  const [selectedInstanceId, setSelectedInstanceId] = useState<string>("agent-alpha");
  const [connStatus, setConnStatus] = useState<"connected" | "connecting" | "disconnected">("connecting");
  const menuletRef = useRef<HTMLDivElement>(null);

  // Sync real digital clock
  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  // Connect to SSE Endpoint /api/v1/monitor/events for real-time fleet synchronization!
  useEffect(() => {
    setConnStatus("connecting");
    const eventSource = new EventSource("/api/v1/monitor/events");

    eventSource.onopen = () => {
      setConnStatus("connected");
      console.log("MouthPeace Cockpit: SSE stream established");
    };

    eventSource.addEventListener("update", (event: any) => {
      try {
        // Safe parsing: strip any raw literal newlines/carriage returns that might have been introduced by SSE line-splitting proxies
        const cleanedData = event.data.replace(/[\n\r]/g, "");
        const snap = JSON.parse(cleanedData);
        setSnapshot(snap);
      } catch (e) {
        console.error("Error parsing snapshot update:", e);
      }
    });

    eventSource.onerror = (err) => {
      setConnStatus("disconnected");
      console.error("MouthPeace Cockpit: SSE error occurred, attempting reconnect:", err);
    };

    return () => {
      eventSource.close();
    };
  }, []);

  // Handle outside clicks to close the menu bar applet dropdown
  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (menuletRef.current && !menuletRef.current.contains(e.target as Node)) {
        setShowMenulet(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  if (!snapshot) {
    return (
      <div className="min-h-screen bg-slate-900 flex flex-col items-center justify-center text-slate-100 font-sans">
        <div className="relative flex flex-col items-center p-8 bg-slate-950/40 backdrop-blur-md rounded-2xl border border-slate-800/80 shadow-2xl">
          <motion.div 
            animate={{ rotate: 360 }}
            transition={{ repeat: Infinity, duration: 2, ease: "linear" }}
            className="w-12 h-12 border-4 border-indigo-500 border-t-transparent rounded-full mb-4"
          />
          <h2 className="text-xl font-medium text-slate-100 tracking-tight font-sans">
            MouthPeace Cockpit Booting
          </h2>
          <p className="text-sm font-mono text-slate-400 mt-2">
            awaiting channel handshake telemetry...
          </p>
        </div>
      </div>
    );
  }

  const { channels, heartbeats, states, safetyCatches, systemHealth } = snapshot;

  // Global triggers
  const triggerEject = async (id: string) => {
    try {
      await fetch(`/api/v1/monitor/eject/${id}`, { method: "POST" });
    } catch (e) {
      console.error("Failed to trigger panic eject:", e);
    }
  };

  const toggleFloor = async (id: string) => {
    try {
      await fetch(`/api/v1/hub/channel/${id}/floor`, { method: "POST" });
    } catch (e) {
      console.error("Failed to toggle floor:", e);
    }
  };

  const toggleBroadcast = async () => {
    try {
      const nextMode = !broadcastMode;
      setBroadcastMode(nextMode);
      await fetch("/api/v1/hub/broadcast", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ enabled: nextMode })
      });
    } catch (e) {
      console.error("Failed to toggle broadcast:", e);
    }
  };

  const toggleSignal = async (id: string) => {
    try {
      await fetch(`/api/v1/hub/channel/${id}/signal`, { method: "POST" });
    } catch (e) {
      console.error("Failed to toggle channel signal:", e);
    }
  };

  const clearAlert = async (id: string) => {
    try {
      await fetch(`/api/v1/monitor/clear-alert/${id}`, { method: "POST" });
    } catch (e) {
      console.error("Failed to clear channel alert:", e);
    }
  };

  // Background Desktop Wallpapers: Premium macOS Liquid-Glass default dark gradients
  const darkBg = "bg-gradient-to-tr from-slate-950 via-zinc-900 to-indigo-950 text-slate-100";
  const lightBg = "bg-gradient-to-tr from-[#eef2f3] via-[#e5e5e5] to-[#f4f7f6] text-zinc-900";
  const selectedBg = theme === "dark" || (theme === "system" && new Date().getHours() >= 18) ? darkBg : lightBg;

  return (
    <div className={`min-h-screen relative flex flex-col font-sans transition-colors duration-500 overflow-hidden ${selectedBg}`}>
      {/* Dynamic Animated Glass Ambient Orb in Background */}
      <div className="absolute -top-40 -left-40 w-96 h-96 rounded-full bg-indigo-600/10 blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 -right-40 w-[24rem] h-[24rem] rounded-full bg-rose-600/5 blur-3xl pointer-events-none" />

      {/* ==========================================
          1. macOS TOP GLASS MENU BAR
         ========================================== */}
      <header className="w-full h-8 z-50 flex items-center justify-between px-4 select-none border-b text-xs border-white/5 bg-slate-900/15 backdrop-blur-xl">
        <div className="flex items-center space-x-4">
          {/* Apple Logo Placeholder / MouthPeace Logo */}
          <div className="font-semibold flex items-center space-x-1.5 cursor-pointer hover:opacity-80">
            <ShieldAlert id="mp-logo-ic" className="w-4 h-4 text-indigo-400 animate-pulse" />
            <span className="tracking-tight text-white/90">MouthPeace</span>
          </div>

          <span className="text-white/60 font-medium">Cockpit</span>
          <span className="text-white/40">|</span>

          {/* Connection Line Status */}
          <div className="flex items-center space-x-1.5 text-white/70">
            <span className={`w-2 h-2 rounded-full ${
              connStatus === "connected" ? "bg-emerald-400" : connStatus === "connecting" ? "bg-amber-400 animate-pulse" : "bg-rose-400"
            }`} />
            <span className="font-mono uppercase text-[10px] tracking-wider font-semibold">
              {connStatus === "connected" ? "Telemetry Active" : connStatus === "connecting" ? "Syncing..." : "Offline"}
            </span>
          </div>

          <span className="text-white/40">|</span>
          <span className="text-white/60 font-mono hidden md:inline-block">Fleet: {systemHealth.activeChannelsCount}/5 active channels</span>
        </div>

        {/* Right side widgets: Status utilities and Clock */}
        <div className="flex items-center space-x-4 text-white/90">
          {/* Broadcast Trigger Quick Indicator */}
          {broadcastMode && (
            <span className="px-2 py-0.5 rounded-full bg-rose-950 border border-rose-800 text-[9px] uppercase font-bold tracking-widest text-rose-300 flex items-center space-x-1">
              <Zap className="w-2.5 h-2.5" />
              <span>Broadcast Floor</span>
            </span>
          )}

          {/* Speaker Quick Indicator */}
          <div className="flex items-center space-x-1 bg-white/5 hover:bg-white/10 px-2 py-0.5 rounded transition">
            <Mic className="w-3.5 h-3.5 text-indigo-300" />
            <span className="text-[10px] text-white/70">Voice Floor:</span>
            <span className="text-[10px] font-bold text-indigo-200">
              {broadcastMode ? "ALL CHANNELS" : channels.find(c => c.hasFloor)?.name.slice(-2) || "NONE"}
            </span>
          </div>

          {/* Sound / Wireless / Batteries */}
          <Wifi className="w-4 h-4 text-white/70 hover:text-white transition cursor-pointer" />
          <Volume2 className="w-4 h-4 text-white/70 hover:text-white transition cursor-pointer" />

          {/* Theme switcher */}
          <div className="flex items-center p-0.5 rounded bg-white/5 border border-white/5">
            <button 
              onClick={() => setTheme("light")} 
              className={`p-0.5 rounded transition ${theme === "light" ? "bg-white/15 text-indigo-300" : "text-white/40 hover:text-white"}`}
              title="Light Cockpit"
            >
              <Sun className="w-3.5 h-3.5" />
            </button>
            <button 
              onClick={() => setTheme("dark")} 
              className={`p-0.5 rounded transition ${theme === "dark" ? "bg-white/15 text-indigo-300" : "text-white/40 hover:text-white"}`}
              title="Dark Cockpit"
            >
              <Moon className="w-3.5 h-3.5" />
            </button>
          </div>

          {/* ==========================================
              MENULET / BAR WIDGET GRAPHIC BUTTON
             ========================================== */}
          <div className="relative" ref={menuletRef}>
            <button
              onClick={() => setShowMenulet(!showMenulet)}
              className={`flex items-center space-x-1 px-2.5 py-1 rounded-md transition ${
                showMenulet ? "bg-white/15 text-white shadow-md" : "hover:bg-white/5 text-white/80 hover:text-white"
              }`}
            >
              <Sliders className="w-3.5 h-3.5 text-indigo-300" />
              <span className="font-medium">echo-hub</span>
              {channels.some(c => c.alertPulse) && (
                <span className="w-2 h-2 rounded-full bg-rose-500 animate-ping absolute top-0.5 right-0" />
              )}
            </button>

            {/* Menulet Panel Dropdown */}
            <AnimatePresence>
              {showMenulet && (
                <motion.div
                  initial={{ opacity: 0, y: 5 }}
                  animate={{ opacity: 1, y: 2 }}
                  exit={{ opacity: 0, y: 5 }}
                  transition={{ duration: 0.15 }}
                  className="absolute right-0 top-6 w-80 bg-[#1e2230]/95 backdrop-blur-2xl border border-white/10 rounded-xl overflow-hidden shadow-2xl z-50 text-slate-100"
                >
                  <div className="p-3 border-b border-slate-800 flex items-center justify-between">
                    <span className="font-semibold tracking-tight text-slate-200">echo-hub Control Surface</span>
                    <span className="px-1.5 py-0.5 rounded text-[9px] bg-indigo-950 border border-indigo-700/80 text-indigo-300 font-mono">
                      v1.4.1 Swift macOS
                    </span>
                  </div>

                  {/* Channel Status Quick Cards inside Menu Bar Applet */}
                  <div className="p-2 space-y-1.5 max-h-60 overflow-y-auto">
                    {channels.map((chan) => {
                      const hb = chan.pairedInstanceId ? heartbeats[chan.pairedInstanceId] : null;
                      const buddyState = chan.pairedInstanceId ? states[chan.pairedInstanceId] : "sleep";

                      return (
                        <div 
                          key={chan.id} 
                          className={`p-2 rounded-lg border flex flex-col justify-between transition ${
                            chan.alertPulse 
                              ? "bg-rose-950/40 border-rose-700/80 hover:bg-rose-950/60" 
                              : "bg-slate-900/40 border-slate-800 hover:bg-slate-900/60"
                          }`}
                        >
                          <div className="flex items-center justify-between">
                            <div className="flex items-center space-x-2">
                              {/* Colored indicator dot */}
                              <span 
                                className={`w-3 h-3 rounded-full border border-black/30 ${
                                  chan.alertPulse ? "animate-pulse" : ""
                                }`} 
                                style={{ backgroundColor: chan.color }}
                              />
                              <span className="font-semibold text-xs text-slate-200">{chan.name}</span>
                              <span className="text-[10px] uppercase font-mono px-1 py-0.2 bg-white/5 rounded text-white/60">
                                {chan.id}
                              </span>
                            </div>

                            {/* State Badge */}
                            <span className={`text-[9px] font-mono font-bold px-1.5 py-0.5 rounded border ${
                              buddyState === "idle" ? "bg-slate-900 text-slate-400 border-slate-800" :
                              buddyState === "busy" ? "bg-indigo-950 text-indigo-300 border-indigo-800/80 animate-pulse" :
                              buddyState === "attention" ? "bg-amber-950 text-amber-300 border-amber-800/80 animate-bounce" :
                              buddyState === "celebrate" ? "bg-emerald-950 text-emerald-300 border-emerald-800/80" :
                              buddyState === "dizzy" ? "bg-rose-950 text-rose-300 border-rose-800/80 animate-pulse" :
                              "bg-slate-950 text-slate-500 border-slate-900"
                            }`}>
                              {buddyState.toUpperCase()}
                            </span>
                          </div>

                          {chan.alertPulse && (
                            <div className="mt-1.5 text-[10px] text-rose-200 bg-rose-950/50 p-1.5 rounded border border-rose-900">
                              <span className="font-bold flex items-center space-x-1">
                                <AlertOctagon className="w-3.5 h-3.5 mr-1 inline-block" />
                                ALERT TRIPPED
                              </span>
                              <p className="mt-0.5 text-slate-300 truncate">{chan.alertReason}</p>
                            </div>
                          )}

                          {/* Quick audio toggle & button panel */}
                          <div className="flex items-center justify-between mt-2 pt-1.5 min-h-6 border-t border-white/5 text-[10px]">
                            <div className="flex items-center space-x-2">
                              {/* Voice floor button */}
                              <button 
                                onClick={(e) => { e.stopPropagation(); toggleFloor(chan.id); }}
                                className={`px-1.5 py-0.5 rounded border transition flex items-center space-x-1 ${
                                  chan.hasFloor 
                                    ? "bg-indigo-600 border-indigo-500 text-white font-bold" 
                                    : "bg-slate-800/50 border-slate-700 text-slate-300 hover:bg-slate-800"
                                }`}
                                title={chan.hasFloor ? "Muted channel can't speak" : "Lit channel hears voice floor"}
                              >
                                <Mic className="w-2.5 h-2.5" />
                                <span>{chan.hasFloor ? "Speaker ON" : "Unlit"}</span>
                              </button>

                              {/* Trans transceiver toggle */}
                              <button 
                                onClick={(e) => { e.stopPropagation(); toggleSignal(chan.id); }}
                                className={`p-0.5 px-1.5 rounded transition border ${
                                  chan.signalActive 
                                    ? "bg-teal-950 text-teal-300 border-teal-800" 
                                    : "bg-stone-900 text-stone-500 border-stone-800"
                                }`}
                              >
                                <Radio className="w-2.5 h-2.5 inline mr-1" />
                                <span>Signal: {chan.signalActive ? "Tx" : "Mute"}</span>
                              </button>
                            </div>

                            {/* Direct Panic Kill Eject button */}
                            <button
                              onClick={(e) => { e.stopPropagation(); triggerEject(chan.id); }}
                              disabled={chan.ejected}
                              className={`p-0.5 px-2 rounded font-bold border transition flex items-center space-x-1 ${
                                chan.ejected 
                                  ? "bg-rose-950 text-rose-500 border-rose-900 cursor-not-allowed opacity-50" 
                                  : "bg-rose-600 hover:bg-rose-700 text-white border-rose-500"
                              }`}
                            >
                              <Power className="w-2.5 h-2.5" />
                              <span>EJECT</span>
                            </button>
                          </div>
                        </div>
                      );
                    })}
                  </div>

                  {/* Broadcast & volume bar slider simulated controls */}
                  <div className="p-3 bg-slate-900/60 border-t border-slate-800 space-y-2">
                    <div className="flex items-center justify-between text-xs">
                      <span className="text-slate-300 flex items-center space-x-1">
                        <Radio className="w-3.5 h-3.5 text-indigo-400" />
                        <span>Hub Broadcast Mode</span>
                      </span>
                      <button 
                        onClick={toggleBroadcast}
                        className={`text-[9px] uppercase tracking-wider font-bold p-1 px-2 rounded-full border transition ${
                          broadcastMode 
                            ? "bg-rose-600 border-rose-500 text-white animate-pulse" 
                            : "bg-slate-800 border-slate-700 text-slate-400 hover:bg-slate-700"
                        }`}
                      >
                        {broadcastMode ? "BROADCAST ON" : "BROADCAST OFF"}
                      </button>
                    </div>

                    <div className="text-[10px] text-slate-400">
                      Only lit channels hear the human-vocal commands. Use broadcast to override and speak to all 5 channels.
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          {/* Time widget */}
          <span className="font-medium tabular-nums tracking-normal cursor-default select-none hover:text-indigo-200">
            {time.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </span>
        </div>
      </header>

      {/* ==========================================
          2. MAIN MAC DESKTOP DOCK AND DOCK WINDOW
         ========================================== */}
      <main className="flex-1 w-full flex items-center justify-center p-2 sm:p-4 md:p-6 lg:p-8 relative z-10 overflow-hidden">
        
        {/* BUDDY MONITOR DRAGGABLE APP WINDOW */}
        <div id="buddy-window-frame" className="w-full max-w-6xl h-[85vh] rounded-xl border border-white/10 bg-slate-900/60 backdrop-blur-3xl shadow-2xl overflow-hidden flex flex-col transition-all duration-300">
          
          {/* macOS window title bar */}
          <div className="h-10 bg-slate-950/65 flex items-center justify-between px-4 border-b border-white/5 select-none text-xs text-white/50 relative">
            
            {/* macOS traffic lights */}
            <div className="flex items-center space-x-2 z-10">
              <button 
                className="w-3 w-3 h-3 h-3 bg-rose-500 hover:bg-rose-600 rounded-full border border-rose-600/30 flex items-center justify-center group"
                title="Force Close Cockpit"
              >
                <div className="w-1 w-1 h-1 h-1 bg-rose-950 rounded-full opacity-0 group-hover:opacity-100 transition" />
              </button>
              <button 
                className="w-3 w-3 h-3 h-3 bg-amber-500 hover:bg-amber-600 rounded-full border border-amber-600/30 flex items-center justify-center group"
                title="Minimize Cockpit Window"
              >
                <div className="w-1.5 w-0.5 h-0.5 h-0.5 bg-amber-950 rounded-full opacity-0 group-hover:opacity-100 transition" />
              </button>
              <button 
                className="w-3 w-3 h-3 h-3 bg-emerald-500 hover:bg-emerald-600 rounded-full border border-emerald-600/30 flex items-center justify-center group"
                title="Expand Cockpit State"
              >
                <div className="w-1.5 w-1.5 h-1.5 h-1.5 bg-emerald-950 rounded-full opacity-0 group-hover:opacity-100 transition" />
              </button>
            </div>

            {/* Simulated window title & server details */}
            <div className="absolute inset-0 flex items-center justify-center font-medium font-sans text-white/80 pointer-events-none">
              <Activity className="w-3.5 h-3.5 mr-1 text-indigo-400" />
              <span>Buddy Fleet Monitor Dashboard</span>
              <span className="mx-2 text-white/20">|</span>
              <span className="font-mono text-[10px] text-white/40">127.0.0.1:3848</span>
              {connStatus === "connected" && (
                <span className="ml-2 w-1.5 h-1.5 bg-emerald-500 rounded-full" />
              )}
            </div>

            {/* Quick status pill at top-right */}
            <div className="z-10 flex items-center space-x-2">
              <span className="text-[10px] font-mono uppercase font-bold tracking-widest text-[#06b6d4]">
                Liquid Glass Engine v1.0
              </span>
            </div>
          </div>

          {/* ==========================================
              INTERNAL LAYOUT: LEFT SIDEBAR & WORKSPACE
             ========================================== */}
          <div className="flex-1 flex overflow-hidden">
            
            {/* LEFT APP NAVIGATION SIDEBAR */}
            <aside className="w-56 bg-slate-950/40 border-r border-white/5 flex flex-col justify-between p-3 select-none">
              
              <div className="space-y-6">
                <div>
                  <h3 className="text-[10px] font-bold tracking-wider font-sans text-slate-500 uppercase px-2 mb-2">
                    FLEET MONITORS
                  </h3>
                  <nav className="space-y-0.5">
                    <button
                      onClick={() => setSelectedTab("cockpit")}
                      className={`w-full flex items-center justify-between px-2.5 py-1.5 rounded-md text-xs font-medium transition ${
                        selectedTab === "cockpit" 
                          ? "bg-indigo-600/90 text-white" 
                          : "text-slate-300 hover:bg-white/5"
                      }`}
                    >
                      <span className="flex items-center space-x-2">
                        <Activity className="w-4 h-4 text-indigo-400" />
                        <span>Command Center</span>
                      </span>
                      {channels.some(c => c.alertPulse) && (
                        <span className="w-1.5 h-1.5 rounded-full bg-rose-400 animate-pulse" />
                      )}
                    </button>

                    <button
                      onClick={() => setSelectedTab("processes")}
                      className={`w-full flex items-center justify-between px-2.5 py-1.5 rounded-md text-xs font-medium transition ${
                        selectedTab === "processes" 
                          ? "bg-indigo-600/90 text-white" 
                          : "text-slate-300 hover:bg-white/5"
                      }`}
                    >
                      <span className="flex items-center space-x-2">
                        <Cpu className="w-4 h-4 text-pink-400" />
                        <span>Process Board</span>
                      </span>
                      <span className="font-mono text-[9px] font-bold px-1.5 bg-slate-900 border border-slate-700/80 rounded text-slate-300 text-slate-400">
                        {Object.keys(heartbeats).length}
                      </span>
                    </button>

                    <button
                      onClick={() => setSelectedTab("attention")}
                      className={`w-full flex items-center justify-between px-2.5 py-1.5 rounded-md text-xs font-medium transition ${
                        selectedTab === "attention" 
                          ? "bg-indigo-600/90 text-white" 
                          : "text-slate-300 hover:bg-white/5"
                      }`}
                    >
                      <span className="flex items-center space-x-2">
                        <AlertOctagon className="w-4 h-4 text-amber-400 animate-pulse" />
                        <span>Attention Lane</span>
                      </span>
                      {(Object.values(heartbeats) as RuntimeHeartbeat[]).some(hb => hb.pendingPrompt) && (
                        <span className="w-4 h-4 text-[9px] text-slate-100 font-bold bg-amber-600 rounded-full flex items-center justify-center animate-bounce">
                          {(Object.values(heartbeats) as RuntimeHeartbeat[]).filter(hb => hb.pendingPrompt).length}
                        </span>
                      )}
                    </button>

                    <button
                      onClick={() => setSelectedTab("jobs")}
                      className={`w-full flex items-center justify-between px-2.5 py-1.5 rounded-md text-xs font-medium transition ${
                        selectedTab === "jobs" 
                          ? "bg-indigo-600/90 text-white" 
                          : "text-slate-300 hover:bg-white/5"
                      }`}
                    >
                      <span className="flex items-center space-x-2">
                        <Layers className="w-4 h-4 text-emerald-400" />
                        <span>Jobs View</span>
                      </span>
                      <span className="font-mono text-[9px] font-bold px-1.5 bg-slate-900 border border-slate-700/80 rounded text-slate-300 text-emerald-300">
                        {(Object.values(heartbeats) as RuntimeHeartbeat[]).reduce((sum, hb) => sum + hb.jobs.length, 0)}
                      </span>
                    </button>
                  </nav>
                </div>

                <div>
                  <h3 className="text-[10px] font-bold tracking-wider font-sans text-slate-500 uppercase px-2 mb-2 font-semibold">
                    SESSION DIAGNOSTIC
                  </h3>
                  <nav className="space-y-0.5">
                    <button
                      onClick={() => setSelectedTab("detail")}
                      className={`w-full flex items-center justify-between px-2.5 py-1.5 rounded-md text-xs font-medium transition ${
                        selectedTab === "detail" 
                          ? "bg-indigo-600/90 text-white" 
                          : "text-slate-300 hover:bg-white/5"
                      }`}
                    >
                      <span className="flex items-center space-x-2">
                        <Terminal className="w-4 h-4 text-blue-400" />
                        <span>Session Console</span>
                      </span>
                    </button>

                    <button
                      onClick={() => setSelectedTab("health")}
                      className={`w-full flex items-center justify-between px-2.5 py-1.5 rounded-md text-xs font-medium transition ${
                        selectedTab === "health" 
                          ? "bg-indigo-600/90 text-white" 
                          : "text-slate-300 hover:bg-white/5"
                      }`}
                    >
                      <span className="flex items-center space-x-2">
                        <Activity className="w-4 h-4 text-cyan-400" />
                        <span>System Health</span>
                      </span>
                      <span className="text-[10px] uppercase font-bold text-emerald-400">
                        {systemHealth.status.toUpperCase()}
                      </span>
                    </button>
                  </nav>
                </div>

                <div>
                  <h3 className="text-[10px] font-semibold tracking-wider font-sans text-slate-500 uppercase px-2 mb-2">
                    CONFIGURATION
                  </h3>
                  <nav className="space-y-0.5">
                    <button
                      onClick={() => setSelectedTab("settings")}
                      className={`w-full flex items-center justify-between px-2.5 py-1.5 rounded-md text-xs font-medium transition ${
                        selectedTab === "settings" 
                          ? "bg-indigo-600/90 text-white" 
                          : "text-slate-300 hover:bg-white/5"
                      }`}
                    >
                      <span className="flex items-center space-x-2">
                        <Settings className="w-4 h-4 text-teal-300" />
                        <span>Safety Settings</span>
                      </span>
                    </button>
                  </nav>
                </div>
              </div>

              {/* Server Status Monitor Foot */}
              <div className="p-2 border-t border-white/5 space-y-2">
                <div className="flex items-center justify-between text-[11px] text-slate-400">
                  <span>Interventions:</span>
                  <span className="font-mono text-xs font-bold text-rose-300">
                    {systemHealth.safetyInterventionsCount}
                  </span>
                </div>
                <div className="flex items-center justify-between text-[11px] text-slate-400">
                  <span>Stale Streams:</span>
                  <span className="font-mono text-xs font-semibold text-amber-300">
                    {systemHealth.staleHeartbeatsCount}
                  </span>
                </div>
                <div className="flex items-center justify-between text-[11px] text-slate-400">
                  <span>Uptime:</span>
                  <span className="font-mono text-xs text-indigo-300">
                    {Math.floor(systemHealth.uptimeSec / 60)}m {systemHealth.uptimeSec % 60}s
                  </span>
                </div>
              </div>
            </aside>

            {/* COCKPIT WORKSPACE PANEL VIEWPORT */}
            <div className="flex-1 bg-slate-950/15 overflow-y-auto p-4 md:p-6 text-slate-200">
              <AnimatePresence mode="wait">
                <motion.div
                  key={selectedTab}
                  initial={{ opacity: 0, scale: 0.98, y: 5 }}
                  animate={{ opacity: 1, scale: 1, y: 0 }}
                  exit={{ opacity: 0, scale: 0.98, y: 5 }}
                  transition={{ duration: 0.18 }}
                  className="h-full"
                >
                  {selectedTab === "cockpit" && (
                    <CommandCenter 
                      channels={channels}
                      heartbeats={heartbeats}
                      states={states}
                      triggerEject={triggerEject}
                      toggleFloor={toggleFloor}
                      toggleSignal={toggleSignal}
                      clearAlert={clearAlert}
                      onSelectAgent={(id) => {
                        setSelectedInstanceId(id);
                        setSelectedTab("detail");
                      }}
                    />
                  )}

                  {selectedTab === "processes" && (
                    <ProcessBoard
                      heartbeats={heartbeats}
                      states={states}
                      triggerEject={triggerEject}
                      onSelectAgent={(id) => {
                        setSelectedInstanceId(id);
                        setSelectedTab("detail");
                      }}
                      onInjectViolation={async (id, type) => {
                        await fetch(`/api/test/inject/violation/${id}`, {
                          method: "POST",
                          headers: { "Content-Type": "application/json" },
                          body: JSON.stringify({ type })
                        });
                      }}
                      onInjectPrompt={async (id, form) => {
                        await fetch(`/api/test/inject/prompt/${id}`, {
                          method: "POST",
                          headers: { "Content-Type": "application/json" },
                          body: JSON.stringify(form)
                        });
                      }}
                    />
                  )}

                  {selectedTab === "attention" && (
                    <AttentionLane
                      heartbeats={heartbeats}
                      states={states}
                      safetyCatches={safetyCatches}
                      channels={channels}
                      clearAlert={clearAlert}
                      onResolvePrompt={async (id, decision) => {
                        await fetch(`/api/v1/monitor/prompts/${id}/decision`, {
                          method: "POST",
                          headers: { "Content-Type": "application/json" },
                          body: JSON.stringify({ decision })
                        });
                      }}
                    />
                  )}

                  {selectedTab === "jobs" && (
                    <JobsView
                      heartbeats={heartbeats}
                      states={states}
                    />
                  )}

                  {selectedTab === "detail" && (
                    <SessionDetail
                      heartbeats={heartbeats}
                      selectedId={selectedInstanceId}
                      setSelectedId={setSelectedInstanceId}
                    />
                  )}

                  {selectedTab === "health" && (
                    <HealthView
                      systemHealth={systemHealth}
                      heartbeats={heartbeats}
                      states={states}
                      safetyCatches={safetyCatches}
                    />
                  )}

                  {selectedTab === "settings" && (
                    <SafetySettings
                      onInjectSensor={async (id, type, isL0Shadow) => {
                        await fetch(`/api/test/inject/sensor/${id}`, {
                          method: "POST",
                          headers: { "Content-Type": "application/json" },
                          body: JSON.stringify({ type, isL0Shadow })
                        });
                      }}
                      heartbeats={heartbeats}
                    />
                  )}
                </motion.div>
              </AnimatePresence>
            </div>

          </div>
        </div>

      </main>

      {/* Floating Foot Signature */}
      <footer className="h-6 w-full px-4 text-center text-[10px] text-white/35 flex items-center justify-between select-none border-t border-white/5 bg-slate-950/20 backdrop-blur-md">
        <span>© 2026 IndyDevDan. All-mode guard engine active.</span>
        <span>MouthPeace — Multi-Agent Supervision, Floor Control & Eject Seatbelt</span>
      </footer>
    </div>
  );
}
