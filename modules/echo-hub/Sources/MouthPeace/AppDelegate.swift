import AppKit
import Combine
import SwiftUI

/// Bridges all subsystems: menu bar UI, hotkey, MCP server, audio, STT, TTS.
final class AppDelegate: NSObject, NSApplicationDelegate {

   private var statusItem: NSStatusItem!
   private var popover: NSPopover!
   private var hotKeyManager: HotKeyManager!

   let state = AppState()

   // Phase 2 services
   private let mcpServer = MCPServer()
   private let audioService = AudioService()
   private let speechService = SpeechService()
   private let ttsService = TTSService()
   private let speechPatternBridge = SpeechPatternBridge()
   private let restServer = RESTServer()
   private let dialogueOrchestrator = DialogueOrchestrator()
   private var conversationSettings = ConversationSettingsStore.load()
   private let terminalColorAllocator = TerminalSessionColorAllocator()
   private var nextTerminalSessionId = 1
   private let terminalPermissionPromptCooldownSeconds: TimeInterval = 30 * 60
   private var nextTerminalPermissionPromptAllowedAt = Date(timeIntervalSince1970: 0)
   private let terminalPermissionCooldownDefaultsKey =
      "TerminalSessionPermissionPromptCooldownUntil"
   private var speechPermissionGranted = false
   private var speechPermissionRequestInFlight = false

   private var cancellables = Set<AnyCancellable>()
   private var lastTranscriptionText = ""
   private var lastTranscriptionAt = Date(timeIntervalSince1970: 0)
   private let mcpDebounceWindow: TimeInterval = 1.0

   func applicationDidFinishLaunching(_ notification: Notification) {
      state.conversationSettings = conversationSettings
      nextTerminalPermissionPromptAllowedAt = loadTerminalPermissionCooldown()
      audioService.updateSettings(conversationSettings)
      configureStatusItem()
      configurePopover()
      configureHotKey()
      configureTTSFeedbackLoop()
      configureAudioPipeline()
      configureMCPTools()
      configureRESTRoutes()
      restServer.onReady = { [weak self] baseURL in
         self?.state.restBaseURL = baseURL
      }
      mcpServer.shouldSendNotification = { [weak self] sessionId in
         self?.terminalSessionReceivesSignal(sessionId) ?? false
      }
      mcpServer.onClientConnected = { [weak self] candidate in
         self?.registerTerminalSession(candidate)
      }
      mcpServer.onClientIdentityUpdated = { [weak self] sessionId, candidate in
         self?.updateTerminalSession(id: sessionId, candidate: candidate)
      }
      mcpServer.onClientDisconnect = { [weak self] sessionId, reason in
         self?.handleClientDisconnect(sessionId: sessionId, reason: reason)
      }
      restServer.start()
      mcpServer.start()
      observeStateChanges()
   }

   // MARK: - Status item

   private func configureStatusItem() {
      statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      guard let button = statusItem.button else { return }
      button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Echo")
      button.image?.isTemplate = true
      button.title = " Echo"
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
   }

   @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
      let event = NSApp.currentEvent
      if event?.type == .rightMouseUp {
         showStatusMenu()
      } else {
         togglePopover()
      }
   }

   private func showStatusMenu() {
      let menu = NSMenu()
      menu.addItem(withTitle: "Toggle Popover", action: #selector(togglePopover), keyEquivalent: "")
         .target = self
      menu.addItem(NSMenuItem.separator())

      let listenItem = NSMenuItem(
         title: state.isListening ? "Stop Listening" : "Start Listening",
         action: #selector(toggleListening),
         keyEquivalent: "l"
      )
      listenItem.target = self
      menu.addItem(listenItem)

      menu.addItem(NSMenuItem.separator())
      menu.addItem(withTitle: "Quit Echo", action: #selector(quit), keyEquivalent: "q")
         .target = self
      statusItem.menu = menu
      statusItem.button?.performClick(nil)
      DispatchQueue.main.async { [weak self] in
         self?.statusItem.menu = nil
      }
   }

   @objc private func quit() {
      audioService.stopListening()
      NSApp.terminate(nil)
   }

   // MARK: - Popover

   private func configurePopover() {
      popover = NSPopover()
      popover.behavior = .transient
      popover.contentSize = NSSize(width: 420, height: 700)
      let view = PopoverView()
         .environmentObject(state)
      popover.contentViewController = NSHostingController(rootView: view)
   }
   @objc func togglePopover() {
      guard let button = statusItem.button else { return }
      if popover.isShown {
         popover.performClose(nil)
      } else {
         NSApp.activate(ignoringOtherApps: true)
         popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      }
   }

   // MARK: - Hotkey

   private func configureHotKey() {
      hotKeyManager = HotKeyManager()
      // Optional push-to-talk fallback. MouthPeace is hands-free by default,
      // so these handlers only matter after the user explicitly stops listening
      // and turns continuous conversation off through machine control.
      hotKeyManager.onPress = { [weak self] in
         guard let self, !self.state.isContinuousConversation else { return }
         self.startListening()
      }
      hotKeyManager.onRelease = { [weak self] in
         guard let self, !self.state.isContinuousConversation else { return }
         self.stopListening()
      }
      let initial = HotKeyStore.load() ?? HotKey.defaultBinding
      state.currentHotKey = initial
      applyHotKey(initial)
   }

   private func applyHotKey(_ hk: HotKey) {
      let ok = hotKeyManager.register(hk)
      state.lastRegistrationSucceeded = ok
   }

   private func observeStateChanges() {
      state.$currentHotKey
         .dropFirst()
         .sink { [weak self] newValue in
            guard let self else { return }
            HotKeyStore.save(newValue)
            self.applyHotKey(newValue)
         }
         .store(in: &cancellables)

      state.onListeningToggle = { [weak self] listening in
         guard let self else { return }
         if listening {
            self.startListening()
         } else {
            self.stopListening()
         }
      }
      state.onConversationSettingsChange = { [weak self] settings in
         self?.applyConversationSettings(settings)
      }
      state.onTerminalSessionKill = { [weak self] sessionId in
         self?.killTerminalSession(sessionId)
      }
      state.onTerminalSessionSignalChange = { [weak self] sessionId, receivesSignal in
         self?.setTerminalSessionSignal(id: sessionId, receivesSignal: receivesSignal)
      }
   }

   // MARK: - TTS ↔ Audio feedback loop prevention

   private func configureTTSFeedbackLoop() {
      ttsService.onSpeakingStarted = { [weak self] in
         guard let self else { return }
         self.audioService.mute()
         self.speechService.stopRecognition()
         self.state.isSpeaking = true
      }
      ttsService.onSpeakingEnded = { [weak self] in
         // Small delay to avoid capturing tail-end of TTS audio, then hand the
         // floor back to the human microphone automatically.
         DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let self else { return }
            self.audioService.unmute()
            self.state.isSpeaking = false
            self.resumeContinuousListeningAfterSpeech()
         }
      }
      audioService.onInterruption = { [weak self] in
         self?.interruptSpeech(reason: "barge_in")
      }
   }

   private func interruptSpeech(reason: String) {
      guard state.isSpeaking || ttsService.isSpeaking else { return }
      NSLog("MouthPeace: interrupting speech, reason=\(reason)")
      ttsService.stop()
      audioService.unmute()
      state.isSpeaking = false
      state.statusText = "Interrupted"
      dialogueOrchestrator.recordExternalInterruption(reason: reason)
      state.orchestratorStatusText = orchestratorSummary()
      mcpServer.sendNotification(
         method: "notifications/interruption",
         params: ["reason": reason]
      )
      resumeContinuousListeningAfterSpeech()
   }

   // MARK: - Audio → STT pipeline

   private func configureAudioPipeline() {
      audioService.onAudioBuffer = { [weak self] buffer in
         self?.speechService.appendAudio(buffer)
      }
      audioService.onUtterance = { [weak self] _ in
         guard let self else { return }
         guard self.state.isListening else { return }
         self.speechService.stopRecognition {
            guard self.state.isContinuousConversation else { return }
            guard self.state.isListening else { return }
            DispatchQueue.main.async {
               self.speechService.startRecognition(audioFormat: self.audioService.hardwareFormat)
            }
         }
      }
      speechService.onTranscription = { [weak self] text in
         guard let self else { return }
         let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !normalized.isEmpty else { return }
         guard self.shouldEmitTranscription(normalized) else { return }

         self.speechPatternBridge.recordFinalTranscript(normalized)
         self.state.lastTranscription = normalized
         self.state.statusText = "Heard: \(normalized)"
         self.mcpServer.sendNotification(
            method: "notifications/transcription",
            params: ["text": normalized]
         )
      }
      speechService.onPartialResult = { [weak self] text in
         self?.state.statusText = "Hearing: \(text)"
      }
      audioService.onStateChange = { [weak self] audioState in
         guard let self else { return }
         switch audioState {
         case .idle:
            self.state.statusText = "Idle"
         case .listening:
            self.state.statusText = "Listening…"
         case .processing:
            self.state.statusText = "Processing…"
         }
      }
   }

   private static let emptyObjectSchema: [String: Any] = ["type": "object", "properties": [:]]

   private static let dialogueStartSchema: [String: Any] = [
      "type": "object",
      "properties": [
         "dialogueCount": ["type": "integer", "default": 10],
         "dialogueDurationSeconds": ["type": "number", "default": 180],
         "turnIntervalSeconds": ["type": "number", "default": 2.5, "minimum": 2.5],
         "maxTurnsPerDialogue": ["type": "integer"],
         "topic": ["type": "string"],
         "agentA": [
            "type": "object",
            "properties": [
               "name": ["type": "string"],
               "role": ["type": "string"],
            ],
         ],
         "agentB": [
            "type": "object",
            "properties": [
               "name": ["type": "string"],
               "role": ["type": "string"],
            ],
         ],
         "turns": [
            "type": "array",
            "items": [
               "type": "object",
               "properties": [
                  "speaker": ["type": "string"],
                  "text": ["type": "string"],
               ],
               "required": ["speaker", "text"],
            ],
         ],
      ],
      "required": ["turns"],
   ]

   // MARK: - MCP Tools

   private func configureMCPTools() {
      mcpServer.registerTool(
         name: "mission_speak",
         description: "Speak text aloud via text-to-speech. Used to voice the agent's response.",
         inputSchema: [
            "type": "object",
            "properties": [
               "text": ["type": "string", "description": "Text to speak aloud"]
            ],
            "required": ["text"],
         ]
      ) { [weak self] params in
         guard let self else { throw ToolError.serviceUnavailable }
         guard let text = params["text"] as? String else {
            throw ToolError.invalidParams("Missing 'text' parameter")
         }
         self.speakSynchronously(text)
         return ["status": "spoken", "length": text.count]
      }

      mcpServer.registerTool(
         name: "mission_start_listening",
         description: "Start capturing audio from the microphone and transcribing speech.",
         inputSchema: ["type": "object", "properties": [:]]
      ) { [weak self] _ in
         guard let self else { throw ToolError.serviceUnavailable }
         self.runOnMainSync {
            self.state.isContinuousConversation = true
            self.startListening()
         }
         return ["status": self.state.isListening ? "listening" : "not_listening"]
      }

      mcpServer.registerTool(
         name: "mission_stop_listening",
         description: "Stop capturing audio from the microphone.",
         inputSchema: ["type": "object", "properties": [:]]
      ) { [weak self] _ in
         guard let self else { throw ToolError.serviceUnavailable }
         self.runOnMainSync {
            self.state.isContinuousConversation = false
            self.stopListening()
         }
         return ["status": "stopped"]
      }

      mcpServer.registerTool(
         name: "mission_continue",
         description: "Continue the active speech session if it was interrupted.",
         inputSchema: ["type": "object", "properties": [:]]
      ) { [weak self] _ in
         guard let self else { throw ToolError.serviceUnavailable }
         self.runOnMainSync {
            self.state.isContinuousConversation = true
            if !self.state.isListening {
               self.startListening()
            }
         }
         return ["status": self.state.isListening ? "continued" : "not_listening"]
      }

      mcpServer.registerTool(
         name: "mission_interrupt",
         description: "Interrupt current text-to-speech playback and resume listening.",
         inputSchema: ["type": "object", "properties": [:]]
      ) { [weak self] _ in
         guard let self else { throw ToolError.serviceUnavailable }
         let wasSpeaking = self.state.isSpeaking || self.ttsService.isSpeaking
         self.runOnMainSync {
            self.interruptSpeech(reason: "tool")
         }
         return ["status": wasSpeaking ? "interrupted" : "idle"]
      }
      mcpServer.registerTool(
         name: "mission_clear_session",
         description: "Stop transcription and playback, and reset transient state.",
         inputSchema: ["type": "object", "properties": [:]]
      ) { [weak self] _ in
         guard let self else { throw ToolError.serviceUnavailable }
         self.runOnMainSync {
            self.ttsService.stop()
            self.state.isContinuousConversation = false
            self.stopListening()
            self.lastTranscriptionText = ""
            self.lastTranscriptionAt = Date(timeIntervalSince1970: 0)
            self.state.lastTranscription = nil
            DispatchQueue.main.async {
               self.state.statusText = "Session cleared"
            }
         }
         return ["status": "cleared"]
      }

      mcpServer.registerTool(
         name: "mission_get_status",
         description:
            "Get the current status of MouthPeace: listening state, last transcription, speaking state.",
         inputSchema: ["type": "object", "properties": [:]]
      ) { [weak self] _ in
         guard let self else { throw ToolError.serviceUnavailable }
         return self.statusDictionary()
      }

      mcpServer.registerTool(
         name: "mission_start_agent_dialogues",
         description:
            "Play supplied LLM-generated two-subagent turns under the local audible orchestrator.",
         inputSchema: Self.dialogueStartSchema
      ) { [weak self] params in
         guard let self else { throw ToolError.serviceUnavailable }
         let request = try DialogueOrchestrator.StartRequest(params: params)
         let snapshot = try self.dialogueOrchestrator.start(request: request) {
            [weak self] text, completion in
            guard let self else {
               completion()
               return
            }
            DispatchQueue.main.async {
               self.ttsService.speak(text, completion: completion)
            }
         }
         self.updateOrchestratorState(snapshot)
         return ["orchestrator": snapshot.dictionary]
      }

      mcpServer.registerTool(
         name: "mission_get_orchestrator_status",
         description:
            "Return current orchestrator state, dialogue counters, recent turn events, and collected errors.",
         inputSchema: ["type": "object", "properties": [:]]
      ) { [weak self] _ in
         guard let self else { throw ToolError.serviceUnavailable }
         let snapshot = self.dialogueOrchestrator.snapshot()
         self.updateOrchestratorState(snapshot)
         return ["orchestrator": snapshot.dictionary]
      }

      mcpServer.registerTool(
         name: "mission_stop_agent_dialogues",
         description: "Stop the active audible two-subagent dialogue session.",
         inputSchema: ["type": "object", "properties": [:]]
      ) { [weak self] _ in
         guard let self else { throw ToolError.serviceUnavailable }
         let snapshot = self.dialogueOrchestrator.stop()
         self.updateOrchestratorState(snapshot)
         return ["orchestrator": snapshot.dictionary]
      }

   }

   // MARK: - REST API

   private func configureRESTRoutes() {
      restServer.register(
         RESTEndpoint(
            method: "GET",
            path: "/v1/openapi",
            description: "Return the authenticated LLM-first REST endpoint catalog.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["endpoints"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               return RESTResponse(body: [
                  "name": "MouthPeace",
                  "version": "1.0",
                  "auth": "Bearer token in Authorization header",
                  "errorShape": [
                     "error": [
                        "code": "machine_readable_string",
                        "message": "human readable string",
                        "requestId": "request correlation id",
                     ]
                  ],
                  "endpoints": self.restServer.catalog(),
               ])
            }))

      restServer.register(
         RESTEndpoint(
            method: "GET",
            path: "/v1/status",
            description:
               "Return runtime state for listening, speech, REST, hotkey, settings, connected terminal sessions, and orchestrator.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: [
               "type": "object", "required": ["isListening", "terminalSessions", "orchestrator"],
            ],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               return RESTResponse(body: self.statusDictionary())
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/speech/speak",
            description: "Speak text aloud through the same TTS engine used by the MCP partner.",
            requestSchema: [
               "type": "object",
               "properties": ["text": ["type": "string"]],
               "required": ["text"],
            ],
            responseSchema: ["type": "object", "required": ["status", "length"]],
            handler: { [weak self] body in
               guard let self else { throw ToolError.serviceUnavailable }
               guard let text = body["text"] as? String, !text.isEmpty else {
                  throw RESTError.validation("Missing non-empty 'text' parameter")
               }
               self.speakSynchronously(text)
               return RESTResponse(body: ["status": "spoken", "length": text.count])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/listening/start",
            description: "Start microphone capture and continuous speech recognition.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["status"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               self.runOnMainSync {
                  self.state.isContinuousConversation = true
                  self.startListening()
               }
               return RESTResponse(body: [
                  "status": self.state.isListening ? "listening" : "not_listening"
               ])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/listening/stop",
            description: "Stop microphone capture and continuous speech recognition.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["status"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               self.runOnMainSync {
                  self.state.isContinuousConversation = false
                  self.stopListening()
               }
               return RESTResponse(body: ["status": "stopped"])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/session/continue",
            description: "Continue or resume an interrupted conversation session.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["status"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               self.runOnMainSync {
                  self.state.isContinuousConversation = true
                  if !self.state.isListening {
                     self.startListening()
                  }
               }
               return RESTResponse(body: [
                  "status": self.state.isListening ? "continued" : "not_listening"
               ])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/session/interrupt",
            description: "Interrupt current text-to-speech playback and resume listening.",
            requestSchema: [
               "type": "object",
               "properties": ["reason": ["type": "string"]],
            ],
            responseSchema: ["type": "object", "required": ["status"]],
            handler: { [weak self] body in
               guard let self else { throw ToolError.serviceUnavailable }
               let reason = (body["reason"] as? String) ?? "rest"
               let wasSpeaking = self.state.isSpeaking || self.ttsService.isSpeaking
               self.runOnMainSync {
                  self.interruptSpeech(reason: reason)
               }
               return RESTResponse(body: ["status": wasSpeaking ? "interrupted" : "idle"])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/session/clear",
            description:
               "Stop transcription and playback, reset transient session state, and stop orchestrator dialogue.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["status"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               let snapshot = self.dialogueOrchestrator.stop()
               self.runOnMainSync {
                  self.ttsService.stop()
                  self.state.isContinuousConversation = false
                  self.stopListening()
                  self.lastTranscriptionText = ""
                  self.lastTranscriptionAt = Date(timeIntervalSince1970: 0)
                  self.state.lastTranscription = nil
                  self.state.statusText = "Session cleared"
               }
               self.updateOrchestratorState(snapshot)
               return RESTResponse(body: ["status": "cleared"])
            }))

      restServer.register(
         RESTEndpoint(
            method: "GET",
            path: "/v1/hotkey",
            description: "Return the current global push-to-talk hotkey binding.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["hotKey"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               return RESTResponse(body: ["hotKey": self.hotKeyDictionary(self.state.currentHotKey)]
               )
            }))

      restServer.register(
         RESTEndpoint(
            method: "PUT",
            path: "/v1/hotkey",
            description: "Set the global push-to-talk hotkey binding.",
            requestSchema: [
               "type": "object",
               "properties": [
                  "keyCode": ["type": "integer"],
                  "modifiers": ["type": "integer"],
               ],
               "required": ["keyCode", "modifiers"],
            ],
            responseSchema: ["type": "object", "required": ["hotKey", "registered"]],
            handler: { [weak self] body in
               guard let self else { throw ToolError.serviceUnavailable }
               guard let keyCode = body["keyCode"] as? Int,
                  let modifiers = body["modifiers"] as? Int
               else {
                  throw RESTError.validation("'keyCode' and 'modifiers' must be integers")
               }
               let hotKey = HotKey(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
               self.runOnMainSync {
                  self.state.currentHotKey = hotKey
                  HotKeyStore.save(hotKey)
                  self.applyHotKey(hotKey)
               }
               return RESTResponse(body: [
                  "hotKey": self.hotKeyDictionary(hotKey),
                  "registered": self.state.lastRegistrationSucceeded,
               ])
            }))

      restServer.register(
         RESTEndpoint(
            method: "GET",
            path: "/v1/settings/conversation",
            description: "Return human-owned turn and barge-in timing settings.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["settings"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               return RESTResponse(body: ["settings": self.conversationSettings.dictionary])
            }))

      restServer.register(
         RESTEndpoint(
            method: "PUT",
            path: "/v1/settings/conversation",
            description: "Update human-owned turn and barge-in timing settings.",
            requestSchema: [
               "type": "object",
               "properties": [
                  "humanTurnSilenceSeconds": ["type": "number"],
                  "bargeInThreshold": ["type": "number"],
                  "bargeInRequiredFrames": ["type": "integer"],
                  "bargeInArmDelaySeconds": ["type": "number"],
               ],
            ],
            responseSchema: ["type": "object", "required": ["settings"]],
            handler: { [weak self] body in
               guard let self else { throw ToolError.serviceUnavailable }
               let settings = try ConversationSettings(
                  dictionary: body, fallback: self.conversationSettings)
               self.applyConversationSettings(settings)
               return RESTResponse(body: ["settings": settings.dictionary])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/orchestrator/dialogues/start",
            description:
               "Play supplied LLM-generated two-subagent turns with enforced audible handoff timing.",
            requestSchema: Self.dialogueStartSchema,
            responseSchema: ["type": "object", "required": ["orchestrator"]],
            handler: { [weak self] body in
               guard let self else { throw ToolError.serviceUnavailable }
               let request = try DialogueOrchestrator.StartRequest(params: body)
               let snapshot = try self.dialogueOrchestrator.start(request: request) {
                  [weak self] text, completion in
                  guard let self else {
                     completion()
                     return
                  }
                  DispatchQueue.main.async {
                     self.ttsService.speak(text, completion: completion)
                  }
               }
               self.updateOrchestratorState(snapshot)
               return RESTResponse(status: 202, body: ["orchestrator": snapshot.dictionary])
            }))

      restServer.register(
         RESTEndpoint(
            method: "GET",
            path: "/v1/orchestrator/dialogues/status",
            description:
               "Return dialogue session progress, recent spoken turns, and collected errors.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["orchestrator"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               let snapshot = self.dialogueOrchestrator.snapshot()
               self.updateOrchestratorState(snapshot)
               return RESTResponse(body: ["orchestrator": snapshot.dictionary])
            }))

      restServer.register(
         RESTEndpoint(
            method: "GET",
            path: "/v1/orchestrator/dialogues/markdown",
            description:
               "Export the current dialogue transcript as Markdown for artifact retention.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["filename", "turns", "markdown"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               return RESTResponse(body: self.dialogueOrchestrator.markdownTranscript())
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/orchestrator/dialogues/stop",
            description: "Stop the active audible two-subagent dialogue session.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["orchestrator"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               let snapshot = self.dialogueOrchestrator.stop()
               self.updateOrchestratorState(snapshot)
               return RESTResponse(body: ["orchestrator": snapshot.dictionary])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/popover/toggle",
            description: "Toggle the MouthPeace popover UI.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["status"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               self.runOnMainSync { self.togglePopover() }
               return RESTResponse(body: ["status": "toggled"])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/microphone/open-settings",
            description: "Open macOS microphone privacy settings.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["status"]],
            handler: { _ in
               DispatchQueue.main.async {
                  MicrophonePermission.openSystemSettings()
               }
               return RESTResponse(body: ["status": "opened"])
            }))

      restServer.register(
         RESTEndpoint(
            method: "GET",
            path: "/v1/terminal-sessions",
            description: "Return the Echo console registry of connected terminal sessions.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["terminalSessions"]],
            handler: { [weak self] _ in
               guard let self else { throw ToolError.serviceUnavailable }
               return RESTResponse(body: ["terminalSessions": self.terminalSessionDictionaries()])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/terminal-sessions/kill",
            description: "Immediately kill a connected terminal session by Echo session id.",
            requestSchema: [
               "type": "object",
               "properties": ["id": ["type": "integer"]],
               "required": ["id"],
            ],
            responseSchema: ["type": "object", "required": ["status", "id"]],
            handler: { [weak self] body in
               guard let self else { throw ToolError.serviceUnavailable }
               let id: Int?
               if let number = body["id"] as? NSNumber {
                  id = number.intValue
               } else {
                  id = body["id"] as? Int
               }
               guard let id else {
                  throw RESTError.validation("Missing integer 'id' parameter")
               }
               guard self.terminalSessionExists(id) else {
                  throw RESTError.notFound("No terminal session with id \(id)")
               }
               self.killTerminalSession(id)
               return RESTResponse(body: ["status": "killed", "id": id])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/terminal-sessions/revoke",
            description: "Compatibility alias for immediately killing a terminal session.",
            requestSchema: [
               "type": "object",
               "properties": ["id": ["type": "integer"]],
               "required": ["id"],
            ],
            responseSchema: ["type": "object", "required": ["status", "id"]],
            handler: { [weak self] body in
               guard let self else { throw ToolError.serviceUnavailable }
               let id: Int?
               if let number = body["id"] as? NSNumber {
                  id = number.intValue
               } else {
                  id = body["id"] as? Int
               }
               guard let id else {
                  throw RESTError.validation("Missing integer 'id' parameter")
               }
               guard self.terminalSessionExists(id) else {
                  throw RESTError.notFound("No terminal session with id \(id)")
               }
               self.killTerminalSession(id)
               return RESTResponse(body: ["status": "killed", "id": id])
            }))

      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/terminal-sessions/signal",
            description: "Enable or disable signal delivery for a terminal session channel.",
            requestSchema: [
               "type": "object",
               "properties": [
                  "id": ["type": "integer"],
                  "receivesSignal": ["type": "boolean"],
               ],
               "required": ["id", "receivesSignal"],
            ],
            responseSchema: [
               "type": "object",
               "required": ["status", "id", "receivesSignal"],
            ],
            handler: { [weak self] body in
               guard let self else { throw ToolError.serviceUnavailable }
               let id: Int?
               if let number = body["id"] as? NSNumber {
                  id = number.intValue
               } else {
                  id = body["id"] as? Int
               }
               guard let id else {
                  throw RESTError.validation("Missing integer 'id' parameter")
               }
               guard let receivesSignal = body["receivesSignal"] as? Bool else {
                  throw RESTError.validation("Missing boolean 'receivesSignal' parameter")
               }
               guard self.terminalSessionExists(id) else {
                  throw RESTError.notFound("No terminal session with id \(id)")
               }
               self.setTerminalSessionSignal(id: id, receivesSignal: receivesSignal)
               return RESTResponse(body: [
                  "status": "updated",
                  "id": id,
                  "receivesSignal": receivesSignal,
               ])
            }))
      restServer.register(
         RESTEndpoint(
            method: "POST",
            path: "/v1/app/quit",
            description: "Terminate MouthPeace after returning the response.",
            requestSchema: Self.emptyObjectSchema,
            responseSchema: ["type": "object", "required": ["status"]],
            handler: { _ in
               DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  NSApp.terminate(nil)
               }
               return RESTResponse(body: ["status": "terminating"])
            }))
   }

   private func runOnMainSync(_ work: @escaping () -> Void) {
      if Thread.isMainThread {
         work()
         return
      }
      let semaphore = DispatchSemaphore(value: 0)
      DispatchQueue.main.async {
         work()
         semaphore.signal()
      }
      semaphore.wait()
   }

   private func speakSynchronously(_ text: String) {
      let semaphore = DispatchSemaphore(value: 0)
      DispatchQueue.main.async {
         self.ttsService.speak(text) {
            semaphore.signal()
         }
      }
      semaphore.wait()
   }

   private func statusDictionary() -> [String: Any] {
      var result: [String: Any] = [:]
      runOnMainSync {
         let orchestratorSnapshot = self.dialogueOrchestrator.snapshot()
         result = [
            "isListening": self.state.isListening,
            "isSpeaking": self.state.isSpeaking,
            "isContinuousConversation": self.state.isContinuousConversation,
            "lastTranscription": self.state.lastTranscription ?? "",
            "statusText": self.state.statusText,
            "conversationSettings": self.conversationSettings.dictionary,
            "hotKey": self.hotKeyDictionary(self.state.currentHotKey),
            "orchestrator": orchestratorSnapshot.dictionary,
            "terminalSessions": self.state.terminalSessions.map { $0.dictionary },
            "terminalPermission": self.terminalPermissionDictionary(),
            "rest": self.restServer.statusDictionary(),
         ]
      }
      return result
   }

   private func applyConversationSettings(_ settings: ConversationSettings) {
      let sanitized = settings.sanitized
      runOnMainSync {
         self.conversationSettings = sanitized
         ConversationSettingsStore.save(sanitized)
         self.audioService.updateSettings(sanitized)
         self.state.conversationSettings = sanitized
      }
   }

   private func updateOrchestratorState(_ snapshot: DialogueOrchestrator.Snapshot) {
      let summary = orchestratorSummary(snapshot)
      if Thread.isMainThread {
         state.orchestratorStatusText = summary
      } else {
         DispatchQueue.main.async { [weak self] in
            self?.state.orchestratorStatusText = summary
         }
      }
   }

   private func orchestratorSummary() -> String {
      orchestratorSummary(dialogueOrchestrator.snapshot())
   }

   private func orchestratorSummary(_ snapshot: DialogueOrchestrator.Snapshot) -> String {
      if snapshot.isRunning {
         return
            "Dialogue \(snapshot.currentDialogueIndex)/\(snapshot.totalDialogues) · \(snapshot.turnsCompleted) turns · \(snapshot.errors.count) errors"
      }
      return
         "Orchestrator idle · \(snapshot.turnsCompleted) turns · \(snapshot.errors.count) errors"
   }

   private func hotKeyDictionary(_ hotKey: HotKey) -> [String: Any] {
      [
         "keyCode": hotKey.keyCode,
         "modifiers": hotKey.modifiers,
         "display": hotKey.displayString,
      ]
   }

   // MARK: - Listening control

   @objc private func toggleListening() {
      if state.isListening {
         stopListening()
      } else {
         startListening()
      }
   }

   private func startListening() {
      guard !state.isListening else { return }
      guard speechPermissionGranted else {
         guard !speechPermissionRequestInFlight else { return }
         speechPermissionRequestInFlight = true
         requestSpeechPermission { [weak self] granted in
            guard let self else { return }
            self.speechPermissionRequestInFlight = false
            if granted {
               self.startListening()
            }
         }
         return
      }

      do {
         speechService.startRecognition(audioFormat: audioService.hardwareFormat)
         try audioService.startListening()
         state.isListening = true
      } catch {
         NSLog("MouthPeace: failed to start listening: \(error)")
         state.statusText = "Error: \(error.localizedDescription)"
         state.isListening = false
      }
   }

   private func stopListening() {
      guard state.isListening else { return }
      audioService.stopListening()
      speechService.stopRecognition()
      state.isListening = false
   }

   private func resumeContinuousListeningAfterSpeech() {
      guard state.isContinuousConversation else { return }
      if !state.isListening {
         startListening()
         return
      }
      audioService.resumeListening()
      if !speechService.isRecognizing {
         speechService.startRecognition(audioFormat: audioService.hardwareFormat)
      }
      state.statusText = "Listening…"
   }

   private func registerTerminalSession(_ candidate: TerminalSessionCandidate) -> TerminalSession? {
      let decision = terminalSessionApprovalDecision(candidate)
      guard decision.approved else {
         denyTerminalSession(candidate, reason: decision.reason)
         return nil
      }

      var registered: TerminalSession!
      runOnMainSync {
         let id = self.nextTerminalSessionId
         let color = self.terminalColorAllocator.nextColor()
         let receivesSignal = !self.state.terminalSessions.contains {
            $0.state == .connected && $0.receivesSignal
         }
         registered = TerminalSession(
            id: id,
            channelId: "ch_terminal_\(id)",
            label: candidate.label,
            processName: candidate.processName,
            parentProcessID: candidate.parentProcessID,
            transport: candidate.transport,
            terminalApplication: candidate.terminalApplication,
            terminalApplicationVersion: candidate.terminalApplicationVersion,
            terminalApplicationProcessID: candidate.terminalApplicationProcessID,
            terminalSessionIdentifier: candidate.terminalSessionIdentifier,
            terminalPaneIdentifier: candidate.terminalPaneIdentifier,
            agentTopBarText: candidate.agentTopBarText,
            clientName: candidate.clientName,
            clientVersion: candidate.clientVersion,
            colorName: color.name,
            colorHex: color.hex,
            connectedAt: Date(),
            state: .connected,
            permissionState: .approved,
            receivesSignal: receivesSignal)
         self.nextTerminalSessionId += 1
         self.state.terminalSessions.append(registered)
         self.state.statusText = "\(registered.displayIdentifier) approved"
         self.state.terminalPermissionStatusText = "approved"
      }
      return registered
   }

   private func updateTerminalSession(
      id: Int,
      candidate: TerminalSessionCandidate
   ) -> TerminalSession? {
      var updated: TerminalSession?
      runOnMainSync {
         guard let index = self.state.terminalSessions.firstIndex(where: { $0.id == id }) else {
            return
         }
         var session = self.state.terminalSessions[index]
         session.label = candidate.label
         session.processName = candidate.processName
         session.parentProcessID = candidate.parentProcessID
         session.transport = candidate.transport
         session.terminalApplication = candidate.terminalApplication
         session.terminalApplicationVersion = candidate.terminalApplicationVersion
         session.terminalApplicationProcessID = candidate.terminalApplicationProcessID
         session.terminalSessionIdentifier = candidate.terminalSessionIdentifier
         session.terminalPaneIdentifier = candidate.terminalPaneIdentifier
         session.agentTopBarText = candidate.agentTopBarText
         session.clientName = candidate.clientName
         session.clientVersion = candidate.clientVersion
         session.state = .connected
         session.permissionState = .approved
         self.state.terminalSessions[index] = session
         updated = session
      }
      return updated
   }

   private func terminalSessionExists(_ id: Int) -> Bool {
      var exists = false
      runOnMainSync {
         exists = self.state.terminalSessions.contains { $0.id == id }
      }
      return exists
   }

   private func killTerminalSession(_ id: Int) {
      let displayName = terminalSessionDisplayName(id)
      setTerminalPermissionCooldown(
         until: Date().addingTimeInterval(terminalPermissionPromptCooldownSeconds))
      guard mcpServer.killSession(id: id) else {
         markTerminalSession(id: id, state: .disconnected, permissionState: .killed)
         state.statusText = "\(displayName) killed"
         state.terminalPermissionStatusText = "killed"
         return
      }
      markTerminalSession(id: id, state: .disconnected, permissionState: .killed)
      state.statusText = "\(displayName) killed"
      state.terminalPermissionStatusText = "killed"
   }

   private func setTerminalSessionSignal(id: Int, receivesSignal: Bool) {
      runOnMainSync {
         guard let index = self.state.terminalSessions.firstIndex(where: { $0.id == id }) else {
            return
         }
         self.state.terminalSessions[index].receivesSignal = receivesSignal
         let displayName = self.state.terminalSessions[index].displayIdentifier
         self.state.statusText =
            receivesSignal
            ? "Signal enabled for \(displayName)"
            : "Signal disabled for \(displayName)"
      }
   }

   private func terminalSessionDisplayName(_ id: Int) -> String {
      var displayName = "Echo session #\(id)"
      runOnMainSync {
         if let session = self.state.terminalSessions.first(where: { $0.id == id }) {
            displayName = session.displayIdentifier
         }
      }
      return displayName
   }

   private func terminalSessionReceivesSignal(_ id: Int?) -> Bool {
      guard let id else { return false }
      var receives = false
      runOnMainSync {
         receives =
            self.state.terminalSessions.first { $0.id == id && $0.state == .connected }?
            .receivesSignal ?? false
      }
      return receives
   }

   private func markTerminalSession(
      id: Int?,
      state newState: TerminalSessionState,
      permissionState newPermissionState: TerminalSessionPermissionState? = nil
   ) {
      guard let id else { return }
      runOnMainSync {
         guard let index = self.state.terminalSessions.firstIndex(where: { $0.id == id }) else {
            return
         }
         var session = self.state.terminalSessions[index]
         session.state = newState
         if let newPermissionState {
            session.permissionState = newPermissionState
         }
         self.state.terminalSessions[index] = session
      }
   }

   private func terminalSessionDictionaries() -> [[String: Any]] {
      var sessions: [[String: Any]] = []
      runOnMainSync {
         sessions = self.state.terminalSessions.map { $0.dictionary }
      }
      return sessions
   }

   private func terminalPermissionDictionary() -> [String: Any] {
      var result: [String: Any] = [:]
      runOnMainSync {
         result = [
            "statusText": self.state.terminalPermissionStatusText,
            "promptCooldownSeconds": self.terminalPermissionPromptCooldownSeconds,
            "canAskNow": Date() >= self.nextTerminalPermissionPromptAllowedAt,
         ]
      }
      return result
   }

   private func handleClientDisconnect(
      sessionId: Int?,
      reason: MCPServer.DisconnectReason
   ) {
      state.isContinuousConversation = false
      stopListening()

      switch reason {
      case .killedByConsole:
         markTerminalSession(id: sessionId, state: .disconnected, permissionState: .killed)
         let idText = sessionId.map { "#\($0)" } ?? "unknown"
         NSLog("MouthPeace: terminal session \(idText) killed from Echo console")
         state.statusText = "Terminal \(idText) killed"
         state.terminalPermissionStatusText = "killed"
      case .endOfFile:
         markTerminalSession(id: sessionId, state: .disconnected)
         NSLog("MouthPeace: host disconnect detected, shutting down")
         state.statusText = "Host disconnected"
         DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if NSApp.isRunning {
               NSApp.terminate(nil)
            } else {
               exit(0)
            }
         }
      }
   }

   private func shouldEmitTranscription(_ text: String) -> Bool {
      let now = Date()
      if text == lastTranscriptionText
         && now.timeIntervalSince(lastTranscriptionAt) < mcpDebounceWindow
      {
         return false
      }
      lastTranscriptionText = text
      lastTranscriptionAt = now
      return true
   }

   private func terminalSessionApprovalDecision(_ candidate: TerminalSessionCandidate)
      -> (approved: Bool, reason: String)
   {
      let now = Date()
      if now < nextTerminalPermissionPromptAllowedAt {
         let remainingSeconds = Int(
            ceil(nextTerminalPermissionPromptAllowedAt.timeIntervalSince(now)))
         return (
            false,
            "additional request denied: permission prompt cooldown active for \(remainingSeconds) seconds"
         )
      }

      let env = ProcessInfo.processInfo.environment
      if env["MOUTHPEACE_DISABLE_SETTINGS_PERSISTENCE"] == "1",
         let override = env["MOUTHPEACE_UNSAFE_TEST_TERMINAL_SESSION_PERMISSION"]?.lowercased()
      {
         if override == "approve" || override == "approved" || override == "allow" {
            return (true, "test override approved")
         }
         if override == "deny" || override == "denied" || override == "reject" {
            setTerminalPermissionCooldown(
               until: now.addingTimeInterval(terminalPermissionPromptCooldownSeconds))
            return (false, "test override denied")
         }
      }
      var approved = false
      runOnMainSync {
         NSApp.activate(ignoringOtherApps: true)
         let alert = NSAlert()
         alert.alertStyle = .warning
         alert.messageText = "Allow Echo session from \(candidate.terminalApplication)?"
         var details = [
            "Terminal: \(candidate.terminalApplication)",
            "Transport: \(candidate.transport)",
            "Parent process: \(candidate.processName) (pid \(candidate.parentProcessID))",
         ]
         if let version = candidate.terminalApplicationVersion {
            details.append("Terminal version: \(version)")
         }
         if let terminalPID = candidate.terminalApplicationProcessID {
            details.append("Terminal process: pid \(terminalPID)")
         }
         if let terminalSession = candidate.terminalSessionIdentifier {
            details.append("Terminal session: \(terminalSession)")
         }
         if let pane = candidate.terminalPaneIdentifier {
            details.append("Pane/window: \(pane)")
         }
         if let topBar = candidate.agentTopBarText {
            details.append("Agent top bar: \(topBar)")
         } else {
            details.append("Agent top bar: unavailable from macOS window metadata")
         }
         alert.informativeText =
            "Approval is one-time only. If you deny or kill any session, new session requests are automatically denied for 30 minutes.\n\n"
            + details.joined(separator: "\n")
         alert.addButton(withTitle: "Allow Once")
         alert.addButton(withTitle: "Deny")
         approved = alert.runModal() == .alertFirstButtonReturn
      }
      if !approved {
         setTerminalPermissionCooldown(
            until: now.addingTimeInterval(terminalPermissionPromptCooldownSeconds))
      }
      return (approved, approved ? "human approved" : "human denied")
   }

   private func setTerminalPermissionCooldown(until date: Date) {
      nextTerminalPermissionPromptAllowedAt = date
      guard
         ProcessInfo.processInfo.environment["MOUTHPEACE_DISABLE_SETTINGS_PERSISTENCE"] != "1"
      else { return }
      UserDefaults.standard.set(
         date.timeIntervalSince1970, forKey: terminalPermissionCooldownDefaultsKey)
   }

   private func loadTerminalPermissionCooldown() -> Date {
      guard
         ProcessInfo.processInfo.environment["MOUTHPEACE_DISABLE_SETTINGS_PERSISTENCE"] != "1"
      else { return Date(timeIntervalSince1970: 0) }
      let timestamp = UserDefaults.standard.double(forKey: terminalPermissionCooldownDefaultsKey)
      guard timestamp > 0 else { return Date(timeIntervalSince1970: 0) }
      let date = Date(timeIntervalSince1970: timestamp)
      if date <= Date() {
         UserDefaults.standard.removeObject(forKey: terminalPermissionCooldownDefaultsKey)
         return Date(timeIntervalSince1970: 0)
      }
      return date
   }

   private func denyTerminalSession(_ candidate: TerminalSessionCandidate, reason: String) {
      runOnMainSync {
         self.state.statusText = "\(candidate.terminalApplication) session denied"
         self.state.terminalPermissionStatusText = reason
      }
      NSLog(
         "MouthPeace: terminal session denied for \(candidate.terminalApplication): \(reason)"
      )
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
         exit(2)
      }
   }

   private func requestSpeechPermission(completion: @escaping (Bool) -> Void = { _ in }) {
      speechService.requestAuthorization { granted in
         self.speechPermissionGranted = granted
         if !granted {
            NSLog("MouthPeace: speech recognition authorization denied")
            self.state.statusText = "Speech recognition denied"
         }
         completion(granted)
      }
   }
}

// MARK: - Shared State

final class AppState: ObservableObject {
   @Published var currentHotKey: HotKey = .defaultBinding
   @Published var lastRegistrationSucceeded: Bool = true
   @Published var isListening: Bool = false
   @Published var isContinuousConversation: Bool = false
   @Published var isSpeaking: Bool = false
   @Published var statusText: String = "Idle"
   @Published var lastTranscription: String?
   @Published var restBaseURL: String = ""
   @Published var conversationSettings: ConversationSettings = .defaults
   @Published var orchestratorStatusText: String = "Orchestrator idle · 0 turns · 0 errors"
   @Published var terminalSessions: [TerminalSession] = []
   var onListeningToggle: ((Bool) -> Void)?
   @Published var terminalPermissionStatusText: String = "No terminal session requested"
   var onTerminalSessionKill: ((Int) -> Void)?
   var onTerminalSessionSignalChange: ((Int, Bool) -> Void)?
   var onConversationSettingsChange: ((ConversationSettings) -> Void)?
}

enum ToolError: LocalizedError {
   case serviceUnavailable
   case invalidParams(String)

   var errorDescription: String? {
      switch self {
      case .serviceUnavailable: return "Service unavailable"
      case .invalidParams(let msg): return "Invalid parameters: \(msg)"
      }
   }
}
