#if canImport(Darwin)
import Darwin
#endif
import Foundation

/// Unix socket server that receives messages from agent hook scripts
final class SocketServer {
    static let shared = SocketServer()

    private let socketPath = Constants.socketPath
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.agentbar.socketserver", qos: .userInitiated)
    private var clientHandlers: [Int32: DispatchWorkItem] = [:]

    /// Pending response continuations keyed by session ID
    private var pendingResponses: [String: (AgentResponse) -> Void] = [:]
    private let responseLock = NSLock()

    private init() {}

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            self?.startServer()
        }
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(socketPath)
    }

    // MARK: - Response Handling

    /// Register a pending response handler for a session
    func registerResponseHandler(sessionId: String, handler: @escaping (AgentResponse) -> Void) {
        responseLock.lock()
        pendingResponses[sessionId] = handler
        responseLock.unlock()
    }

    /// Send a response for a given session (called from UI)
    func sendResponse(sessionId: String, response: AgentResponse) {
        responseLock.lock()
        let handler = pendingResponses.removeValue(forKey: sessionId)
        responseLock.unlock()
        handler?(response)
    }

    // MARK: - Server Implementation

    private func startServer() {
        // Remove existing socket file
        unlink(socketPath)

        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("[AgentBar] Failed to create socket: \(String(cString: strerror(errno)))")
            return
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    let count = min(src.count, 104)
                    dest.assign(from: src.baseAddress!, count: count)
                    return count
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            print("[AgentBar] Failed to bind socket: \(String(cString: strerror(errno)))")
            close(serverSocket)
            return
        }

        // Set permissions so any user process can connect
        chmod(socketPath, 0o777)

        // Listen
        guard listen(serverSocket, 10) == 0 else {
            print("[AgentBar] Failed to listen: \(String(cString: strerror(errno)))")
            close(serverSocket)
            return
        }

        print("[AgentBar] Socket server listening on \(socketPath)")
        isRunning = true

        // Accept loop
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverSocket, sockPtr, &clientLen)
                }
            }

            guard clientSocket >= 0 else {
                if isRunning {
                    print("[AgentBar] Accept failed: \(String(cString: strerror(errno)))")
                }
                continue
            }

            // Handle client on a separate queue
            let workItem = DispatchWorkItem { [weak self] in
                self?.handleClient(clientSocket)
            }
            clientHandlers[clientSocket] = workItem
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        }
    }

    private func handleClient(_ clientSocket: Int32) {
        defer {
            close(clientSocket)
            clientHandlers.removeValue(forKey: clientSocket)
        }

        // Read data from client
        var data = Data()
        let bufferSize = 8192
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = read(clientSocket, buffer, bufferSize)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)

            // Check if we have a complete JSON message (newline-delimited)
            if let lastByte = data.last, lastByte == UInt8(ascii: "\n") {
                break
            }
        }

        guard !data.isEmpty else { return }

        // Parse message
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let message = try? decoder.decode(AgentMessage.self, from: data) else {
            print("[AgentBar] Failed to decode message: \(String(data: data, encoding: .utf8) ?? "?")")
            return
        }

        // Process the message
        let response = processMessage(message)

        // Send response back
        let encoder = JSONEncoder()
        if var responseData = try? encoder.encode(response) {
            responseData.append(UInt8(ascii: "\n"))
            responseData.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress {
                    _ = write(clientSocket, base, responseData.count)
                }
            }
        }
    }

    private func processMessage(_ message: AgentMessage) -> AgentResponse {
        // Post notification for UI updates and sounds
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .agentEventReceived,
                object: nil,
                userInfo: ["event": message.event.rawValue]
            )
        }

        // Update session manager
        let sessionManager = SessionManager.shared

        switch message.event {
        case .sessionStart:
            DispatchQueue.main.async {
                sessionManager.startSession(
                    id: message.sessionId,
                    agentType: message.agentType,
                    workingDirectory: message.workingDirectory ?? "~"
                )
            }
            return .acknowledge()

        case .sessionEnd:
            DispatchQueue.main.async {
                sessionManager.endSession(id: message.sessionId)
            }
            return .acknowledge()

        case .preToolUse, .permissionRequest:
            guard let tool = message.payload.tool else { return .allow() }

            let request = PermissionRequest(
                tool: tool,
                description: message.payload.description ?? "Tool usage request",
                parameters: message.payload.parameters ?? [:]
            )

            // Block until user responds
            let semaphore = DispatchSemaphore(value: 0)
            var userResponse: AgentResponse = .allow()

            DispatchQueue.main.async {
                sessionManager.requestPermission(sessionId: message.sessionId, request: request)
            }

            registerResponseHandler(sessionId: message.sessionId) { response in
                userResponse = response
                semaphore.signal()
            }

            // Wait up to 5 minutes for user response
            let timeout = semaphore.wait(timeout: .now() + 300)
            if timeout == .timedOut {
                DispatchQueue.main.async {
                    sessionManager.clearPermission(sessionId: message.sessionId)
                }
                return .deny()
            }

            return userResponse

        case .postToolUse:
            let toolEvent = ToolEvent(
                tool: message.payload.tool ?? "unknown",
                status: message.payload.status == "denied" ? .denied : .completed
            )
            DispatchQueue.main.async {
                sessionManager.addToolEvent(sessionId: message.sessionId, event: toolEvent)
            }
            return .acknowledge()

        case .askUser:
            guard let question = message.payload.question else { return .acknowledge() }

            let userQuestion = UserQuestion(question: question)

            // Block until user answers
            let semaphore = DispatchSemaphore(value: 0)
            var userResponse: AgentResponse = .acknowledge()

            DispatchQueue.main.async {
                sessionManager.askUser(sessionId: message.sessionId, question: userQuestion)
            }

            registerResponseHandler(sessionId: message.sessionId) { response in
                userResponse = response
                semaphore.signal()
            }

            // Wait up to 10 minutes for user input
            let timeout = semaphore.wait(timeout: .now() + 600)
            if timeout == .timedOut {
                DispatchQueue.main.async {
                    sessionManager.clearQuestion(sessionId: message.sessionId)
                }
                return .answer("")
            }

            return userResponse

        case .notification:
            DispatchQueue.main.async {
                sessionManager.updateTask(
                    sessionId: message.sessionId,
                    task: message.payload.message ?? ""
                )
            }
            return .acknowledge()

        case .planUpdate:
            DispatchQueue.main.async {
                sessionManager.updatePlan(
                    sessionId: message.sessionId,
                    plan: message.payload.plan ?? ""
                )
            }
            return .acknowledge()
        }
    }
}
