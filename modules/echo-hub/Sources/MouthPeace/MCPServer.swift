import Darwin
import Foundation

/// Minimal JSON-RPC 2.0 over stdio MCP server.
/// Reads newline-delimited JSON from stdin on a background thread.
/// Writes responses to stdout. All logging goes to stderr via NSLog.
///
/// The agent (host) launches MouthPeace as a subprocess and communicates
/// via this transport.
final class MCPServer {

   /// Tool handler receives method name and params dict, returns result dict or throws.
   typealias ToolHandler = (_ params: [String: Any]) throws -> [String: Any]

   private var tools: [String: ToolInfo] = [:]
   private var running = false
   private let outputLock = NSLock()
   private let toolQueue = DispatchQueue(
      label: "MouthPeace.MCPServer.tools", qos: .userInitiated, attributes: .concurrent)
   private let connectionLock = NSLock()
   private(set) var isConnected = false
   private var connectedSession: TerminalSession?
   private var disconnectNotified = false
   var onClientConnected: ((TerminalSessionCandidate) -> TerminalSession?)?
   var onClientIdentityUpdated: ((Int, TerminalSessionCandidate) -> TerminalSession?)?
   var onClientDisconnect: ((_ sessionId: Int?, _ reason: DisconnectReason) -> Void)?
   var shouldSendNotification: ((Int?) -> Bool)?

   struct ToolInfo {
      let description: String
      let inputSchema: [String: Any]
      let handler: ToolHandler
   }

   enum DisconnectReason {
      case endOfFile
      case killedByConsole
   }

   // MARK: - Tool Registration

   func registerTool(
      name: String, description: String, inputSchema: [String: Any], handler: @escaping ToolHandler
   ) {
      tools[name] = ToolInfo(description: description, inputSchema: inputSchema, handler: handler)
   }

   // MARK: - Start

   func start() {
      guard !running else { return }

      // Only start stdio transport when stdin is a real pipe/socket from an MCP host.
      // GUI launches via open/Finder often inherit /dev/null: not a TTY, but also not a client.
      var stdinInfo = stat()
      guard fstat(STDIN_FILENO, &stdinInfo) == 0 else {
         NSLog("MouthPeace MCP: failed to inspect stdin, skipping stdio transport")
         return
      }
      let stdinKind = stdinInfo.st_mode & S_IFMT
      guard stdinKind == S_IFIFO || stdinKind == S_IFSOCK else {
         NSLog("MouthPeace MCP: stdin is not an MCP pipe, skipping stdio transport")
         return
      }

      let session: TerminalSession? =
         onClientConnected?(TerminalSessionCandidate.detectStdioClient()) ?? nil
      connectionLock.lock()
      running = true
      isConnected = true
      connectedSession = session
      disconnectNotified = false
      connectionLock.unlock()
      Thread(target: self, selector: #selector(readLoop), object: nil).start()
      NSLog("MouthPeace MCP: stdio server started, \(tools.count) tools registered")
   }

   @discardableResult
   func killSession(id: Int) -> Bool {
      connectionLock.lock()
      let session = connectedSession
      let canKill = isConnected && session?.id == id
      connectionLock.unlock()
      guard canKill, let session else { return false }

      notifyDisconnect(reason: .killedByConsole)
      FileHandle.standardInput.closeFile()
      outputLock.lock()
      FileHandle.standardOutput.closeFile()
      outputLock.unlock()
      terminateClientProcess(for: session)
      return true
   }

   // MARK: - Notification (server → client)

   /// Send a JSON-RPC notification (no id, no response expected).
   func sendNotification(method: String, params: [String: Any]) {
      connectionLock.lock()
      let connected = isConnected
      let sessionId = connectedSession?.id
      connectionLock.unlock()
      guard connected else { return }
      guard shouldSendNotification?(sessionId) ?? true else { return }
      let msg: [String: Any] = [
         "jsonrpc": "2.0",
         "method": method,
         "params": params,
      ]
      writeJSON(msg)
   }

   // MARK: - Stdin read loop

   @objc private func readLoop() {
      let handle = FileHandle.standardInput
      var buffer = Data()

      while running {
         let chunk = handle.availableData
         if chunk.isEmpty {
            // EOF — host closed stdin
            NSLog("MouthPeace MCP: stdin EOF, stopping")
            notifyDisconnect(reason: .endOfFile)
            break
         }

         buffer.append(contentsOf: chunk)
         // Process complete lines
         while let newlineRange = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

            guard !lineData.isEmpty else { continue }
            processMessage(lineData)
         }
      }
   }

   // MARK: - Message processing

   private func processMessage(_ data: Data) {
      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
         NSLog("MouthPeace MCP: failed to parse JSON message")
         return
      }

      let id = json["id"]
      let method = json["method"] as? String ?? ""
      let params = json["params"] as? [String: Any] ?? [:]

      NSLog("MouthPeace MCP: received method=\(method) id=\(id ?? "nil")")

      switch method {
      case "initialize":
         handleInitialize(id: id, params: params)
      case "initialized":
         // Notification from client, no response needed
         NSLog("MouthPeace MCP: client initialized")
      case "tools/list":
         handleToolsList(id: id)
      case "tools/call":
         handleToolsCall(id: id, params: params)
      case "ping":
         sendResult(id: id, result: [:])
      default:
         sendError(id: id, code: -32601, message: "Method not found: \(method)")
      }
   }

   // MARK: - MCP Protocol Handlers

   private func handleInitialize(id: Any?, params: [String: Any]) {
      let session = updateConnectedSession(withInitializeParams: params) ?? currentSession()
      var result: [String: Any] = [
         "protocolVersion": "2024-11-05",
         "capabilities": [
            "tools": ["listChanged": false],
            "notifications": [:],
         ],
         "serverInfo": [
            "name": "MouthPeace",
            "version": "0.2.0",
         ],
      ]
      if let session {
         result["echoSession"] = session.dictionary
      }
      sendResult(id: id, result: result)
   }

   private func handleToolsList(id: Any?) {
      var toolList: [[String: Any]] = []
      for (name, info) in tools.sorted(by: { $0.key < $1.key }) {
         toolList.append([
            "name": name,
            "description": info.description,
            "inputSchema": info.inputSchema,
         ])
      }
      sendResult(id: id, result: ["tools": toolList])
   }

   private func handleToolsCall(id: Any?, params: [String: Any]) {
      guard let name = params["name"] as? String else {
         sendError(id: id, code: -32602, message: "Missing tool name")
         return
      }
      guard let toolInfo = tools[name] else {
         sendError(id: id, code: -32602, message: "Unknown tool: \(name)")
         return
      }

      let toolParams = params["arguments"] as? [String: Any] ?? [:]

      toolQueue.async { [weak self] in
         do {
            let result = try toolInfo.handler(toolParams)
            let text = Self.encodeJSONText(result)
            let content: [[String: Any]] = [
               ["type": "text", "text": text]
            ]
            self?.sendResult(id: id, result: ["content": content])
         } catch {
            let payload: [String: Any] = [
               "error": error.localizedDescription
            ]
            let text = Self.encodeJSONText(payload)
            let content: [[String: Any]] = [
               ["type": "text", "text": text]
            ]
            self?.sendResult(id: id, result: ["content": content, "isError": true])
         }
      }
   }

   // MARK: - Response helpers

   private func sendResult(id: Any?, result: [String: Any]) {
      var msg: [String: Any] = ["jsonrpc": "2.0", "result": result]
      if let id { msg["id"] = id }
      writeJSON(msg)
   }

   private func sendError(id: Any?, code: Int, message: String) {
      var msg: [String: Any] = [
         "jsonrpc": "2.0",
         "error": ["code": code, "message": message],
      ]
      if let id { msg["id"] = id }
      writeJSON(msg)
   }

   private func writeJSON(_ obj: [String: Any]) {
      guard let data = try? JSONSerialization.data(withJSONObject: obj),
         var str = String(data: data, encoding: .utf8)
      else {
         NSLog("MouthPeace MCP: failed to serialize response")
         return
      }
      str.append("\n")
      outputLock.lock()
      FileHandle.standardOutput.write(str.data(using: .utf8)!)
      outputLock.unlock()
   }

   private func currentSession() -> TerminalSession? {
      connectionLock.lock()
      let session = connectedSession
      connectionLock.unlock()
      return session
   }

   private func updateConnectedSession(withInitializeParams params: [String: Any])
      -> TerminalSession?
   {
      guard let current = currentSession() else { return nil }
      let candidate = TerminalSessionCandidate(
         label: current.label,
         processName: current.processName,
         parentProcessID: current.parentProcessID,
         transport: current.transport,
         terminalApplication: current.terminalApplication,
         terminalApplicationVersion: current.terminalApplicationVersion,
         terminalApplicationProcessID: current.terminalApplicationProcessID,
         terminalSessionIdentifier: current.terminalSessionIdentifier,
         terminalPaneIdentifier: current.terminalPaneIdentifier,
         agentTopBarText: current.agentTopBarText,
         clientName: current.clientName,
         clientVersion: current.clientVersion)
      guard let updatedCandidate = candidate.merged(withInitializeParams: params) else {
         return current
      }
      guard let updatedSession = onClientIdentityUpdated?(current.id, updatedCandidate) else {
         return current
      }
      connectionLock.lock()
      connectedSession = updatedSession
      connectionLock.unlock()
      return updatedSession
   }

   private func terminateClientProcess(for session: TerminalSession) {
      guard shouldTerminateClientProcess else { return }
      let pid = session.parentProcessID
      guard pid > 1 && pid != getpid() else { return }

      NSLog(
         "MouthPeace MCP: killing connected client process pid=\(pid) for session \(session.id)"
      )
      _ = Darwin.kill(pid, SIGTERM)
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
         if Darwin.kill(pid, 0) == 0 {
            _ = Darwin.kill(pid, SIGKILL)
         }
      }
   }

   private var shouldTerminateClientProcess: Bool {
      ProcessInfo.processInfo.environment["MOUTHPEACE_UNSAFE_TEST_DISABLE_CLIENT_PROCESS_KILL"]
         != "1"
   }

   private func notifyDisconnect(reason: DisconnectReason) {
      var sessionId: Int?
      var shouldNotify = false

      connectionLock.lock()
      if !disconnectNotified {
         disconnectNotified = true
         shouldNotify = true
         sessionId = connectedSession?.id
      }
      running = false
      isConnected = false
      connectedSession = nil
      connectionLock.unlock()

      guard shouldNotify else { return }
      DispatchQueue.main.async { [weak self] in
         self?.onClientDisconnect?(sessionId, reason)
      }
   }

   // MARK: - JSON helpers

   /// Serializes a tool result to a compact JSON string.
   /// Falls back to a JSON-quoted Swift description if serialization fails,
   /// so the MCP client always receives valid JSON text.
   private static func encodeJSONText(_ value: [String: Any]) -> String {
      if JSONSerialization.isValidJSONObject(value),
         let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
         let str = String(data: data, encoding: .utf8)
      {
         return str
      }
      let fallback = String(describing: value)
      if let data = try? JSONSerialization.data(withJSONObject: ["raw": fallback], options: []),
         let str = String(data: data, encoding: .utf8)
      {
         return str
      }
      return "{\"error\":\"serialization_failed\"}"
   }
}
