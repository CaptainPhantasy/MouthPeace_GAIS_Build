import Foundation
import Network

struct RESTResponse {
   let status: Int
   let body: [String: Any]

   init(status: Int = 200, body: [String: Any]) {
      self.status = status
      self.body = body
   }
}

struct RESTEndpoint {
   let method: String
   let path: String
   let description: String
   let requestSchema: [String: Any]
   let responseSchema: [String: Any]
   let handler: (_ body: [String: Any]) throws -> RESTResponse

   var catalogEntry: [String: Any] {
      [
         "method": method,
         "path": path,
         "description": description,
         "auth": "bearer",
         "requestSchema": requestSchema,
         "responseSchema": responseSchema,
      ]
   }
}

struct RESTServerConfiguration {
   let host = "127.0.0.1"
   let port: UInt16
   let token: String
   let generatedToken: Bool

   static func fromEnvironment() -> RESTServerConfiguration {
      let env = ProcessInfo.processInfo.environment
      let portValue = UInt16(env["MOUTHPEACE_REST_PORT"] ?? "17383") ?? 17383
      if let token = env["MOUTHPEACE_REST_TOKEN"], !token.isEmpty {
         return RESTServerConfiguration(port: portValue, token: token, generatedToken: false)
      }
      return RESTServerConfiguration(
         port: portValue, token: UUID().uuidString, generatedToken: true)
   }
}

final class RESTServer {
   private let configuration: RESTServerConfiguration
   private let lock = NSLock()
   private var routes: [String: RESTEndpoint] = [:]
   private var listener: NWListener?
   private(set) var baseURL = ""
   private(set) var isRunning = false
   var onReady: ((String) -> Void)?

   init(configuration: RESTServerConfiguration = .fromEnvironment()) {
      self.configuration = configuration
   }

   func register(_ endpoint: RESTEndpoint) {
      lock.lock()
      routes[routeKey(method: endpoint.method, path: endpoint.path)] = endpoint
      lock.unlock()
   }

   func start() {
      guard listener == nil else { return }
      guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
         NSLog("MouthPeace REST: invalid port \(configuration.port)")
         return
      }
      do {
         let listener = try NWListener(using: .tcp, on: port)
         listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
         }
         listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
         }
         self.listener = listener
         listener.start(
            queue: DispatchQueue(label: "MouthPeace.RESTServer.listener", qos: .utility))
      } catch {
         NSLog("MouthPeace REST: failed to start: \(error.localizedDescription)")
      }
   }

   func stop() {
      listener?.cancel()
      listener = nil
      isRunning = false
   }

   func catalog() -> [[String: Any]] {
      lock.lock()
      let values = routes.values.sorted {
         if $0.path == $1.path { return $0.method < $1.method }
         return $0.path < $1.path
      }
      let result = values.map { $0.catalogEntry }
      lock.unlock()
      return result
   }

   func statusDictionary() -> [String: Any] {
      [
         "baseURL": baseURL,
         "auth": "bearer",
         "generatedToken": configuration.generatedToken,
         "isRunning": isRunning,
      ]
   }

   private func handleListenerState(_ state: NWListener.State) {
      switch state {
      case .ready:
         let actualPort = listener?.port?.rawValue ?? configuration.port
         baseURL = "http://\(configuration.host):\(actualPort)"
         isRunning = true
         NSLog("MouthPeace REST: listening on \(baseURL)")
         if configuration.generatedToken {
            NSLog("MouthPeace REST: generated bearer token for this launch")
         }
         DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onReady?(self.baseURL)
         }
      case .failed(let error):
         isRunning = false
         NSLog("MouthPeace REST: listener failed: \(error.localizedDescription)")
      case .cancelled:
         isRunning = false
      default:
         break
      }
   }

   private func accept(_ connection: NWConnection) {
      connection.stateUpdateHandler = { state in
         if case .failed(let error) = state {
            NSLog("MouthPeace REST: connection failed: \(error.localizedDescription)")
         }
      }
      connection.start(
         queue: DispatchQueue(label: "MouthPeace.RESTServer.connection", qos: .utility))
      receive(on: connection, buffer: Data())
   }

   private func receive(on connection: NWConnection, buffer: Data) {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
         [weak self] data, _, isComplete, error in
         guard let self else { return }
         if let error {
            NSLog("MouthPeace REST: receive failed: \(error.localizedDescription)")
            connection.cancel()
            return
         }
         var nextBuffer = buffer
         if let data, !data.isEmpty {
            nextBuffer.append(data)
         }
         if let request = HTTPRequest(data: nextBuffer) {
            self.handle(request, on: connection)
            return
         }
         if isComplete || nextBuffer.count > 128 * 1024 {
            self.sendError(
               .badRequest("Incomplete HTTP request"), requestId: requestId(), on: connection)
            return
         }
         self.receive(on: connection, buffer: nextBuffer)
      }
   }

   private func handle(_ request: HTTPRequest, on connection: NWConnection) {
      let id = requestId()
      guard isAuthorized(request) else {
         sendError(.unauthorized, requestId: id, on: connection)
         return
      }

      lock.lock()
      let endpoint = routes[routeKey(method: request.method, path: request.path)]
      lock.unlock()
      guard let endpoint else {
         sendError(
            .notFound("No endpoint for \(request.method) \(request.path)"), requestId: id,
            on: connection)
         return
      }

      let body: [String: Any]
      do {
         body = try request.jsonBody()
      } catch let error as RESTError {
         sendError(error, requestId: id, on: connection)
         return
      } catch {
         sendError(.badRequest(error.localizedDescription), requestId: id, on: connection)
         return
      }

      do {
         let response = try endpoint.handler(body)
         send(status: response.status, body: response.body, on: connection)
      } catch let restError as RESTError {
         sendError(restError, requestId: id, on: connection)
      } catch let toolError as ToolError {
         sendError(.validation(toolError.localizedDescription), requestId: id, on: connection)
      } catch {
         sendError(.internalServerError, requestId: id, on: connection)
      }
   }

   private func isAuthorized(_ request: HTTPRequest) -> Bool {
      if request.headers["authorization"] == "Bearer \(configuration.token)" {
         return true
      }
      return request.headers["x-mouthpeace-token"] == configuration.token
   }

   private func sendError(_ error: RESTError, requestId: String, on connection: NWConnection) {
      var errorBody: [String: Any] = [
         "code": error.code,
         "message": error.message,
         "requestId": requestId,
      ]
      if let details = error.details {
         errorBody["details"] = details
      }
      send(status: error.status, body: ["error": errorBody], on: connection)
   }

   private func send(status: Int, body: [String: Any], on connection: NWConnection) {
      let payload: Data
      do {
         payload = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
      } catch {
         let fallback = [
            "error": ["code": "serialization_failed", "message": "Response serialization failed"]
         ]
         payload =
            (try? JSONSerialization.data(withJSONObject: fallback, options: [.sortedKeys]))
            ?? Data()
      }
      let headers =
         "HTTP/1.1 \(status) \(reasonPhrase(for: status))\r\n"
         + "Content-Type: application/json\r\n"
         + "Content-Length: \(payload.count)\r\n"
         + "Connection: close\r\n\r\n"
      var response = Data(headers.utf8)
      response.append(payload)
      connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
   }

   private func routeKey(method: String, path: String) -> String {
      "\(method.uppercased()) \(path)"
   }

   private func requestId() -> String {
      "req_\(UUID().uuidString)"
   }

   private func reasonPhrase(for status: Int) -> String {
      switch status {
      case 200: return "OK"
      case 202: return "Accepted"
      case 204: return "No Content"
      case 400: return "Bad Request"
      case 401: return "Unauthorized"
      case 404: return "Not Found"
      case 409: return "Conflict"
      case 422: return "Unprocessable Entity"
      case 500: return "Internal Server Error"
      default: return "OK"
      }
   }
}

private struct HTTPRequest {
   let method: String
   let path: String
   let headers: [String: String]
   let bodyData: Data

   init?(data: Data) {
      let separator = Data("\r\n\r\n".utf8)
      guard let headerRange = data.range(of: separator) else { return nil }
      let headerData = data.subdata(in: data.startIndex..<headerRange.lowerBound)
      guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
      let lines = headerString.components(separatedBy: "\r\n")
      guard let requestLine = lines.first else { return nil }
      let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
      guard requestParts.count >= 2 else { return nil }

      var headers: [String: String] = [:]
      for line in lines.dropFirst() {
         guard let colon = line.firstIndex(of: ":") else { continue }
         let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
         let value = line[line.index(after: colon)...].trimmingCharacters(
            in: .whitespacesAndNewlines)
         headers[key] = value
      }
      let contentLength = Int(headers["content-length"] ?? "0") ?? 0
      let bodyStart = headerRange.upperBound
      guard data.count >= bodyStart + contentLength else { return nil }
      let rawPath = requestParts[1]
      let pathOnly =
         rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(
            String.init) ?? rawPath
      self.method = requestParts[0].uppercased()
      self.path = pathOnly
      self.headers = headers
      self.bodyData = data.subdata(in: bodyStart..<(bodyStart + contentLength))
   }

   func jsonBody() throws -> [String: Any] {
      guard !bodyData.isEmpty else { return [:] }
      guard let object = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
         throw RESTError.badRequest("Request body must be a JSON object")
      }
      return object
   }
}

struct RESTError: Error {
   let status: Int
   let code: String
   let message: String
   let details: [String: Any]?

   static let unauthorized = RESTError(
      status: 401, code: "unauthorized", message: "Missing or invalid bearer token", details: nil)
   static let internalServerError = RESTError(
      status: 500, code: "internal_server_error", message: "Unexpected server error", details: nil)

   static func badRequest(_ message: String) -> RESTError {
      RESTError(status: 400, code: "bad_request", message: message, details: nil)
   }

   static func notFound(_ message: String) -> RESTError {
      RESTError(status: 404, code: "not_found", message: message, details: nil)
   }

   static func conflict(_ message: String) -> RESTError {
      RESTError(status: 409, code: "conflict", message: message, details: nil)
   }

   static func validation(_ message: String) -> RESTError {
      RESTError(status: 422, code: "validation_failed", message: message, details: nil)
   }
}
