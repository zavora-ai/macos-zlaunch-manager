import Foundation

class MCPServer {
    private let serviceManager = ServiceManager()
    private var isRunning = true

    func run() {
        // Read from stdin, write to stdout (JSON-RPC 2.0 over stdio)
        while isRunning {
            guard let line = readLine() else {
                break
            }

            guard let data = line.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let response = handleRequest(request)
            if let responseData = try? JSONSerialization.data(withJSONObject: response),
               let responseString = String(data: responseData, encoding: .utf8) {
                print(responseString)
                fflush(stdout)
            }
        }
    }

    private func handleRequest(_ request: [String: Any]) -> [String: Any] {
        let id = request["id"]
        let method = request["method"] as? String ?? ""
        let params = request["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return makeResponse(id: id, result: handleInitialize(params))
        case "initialized":
            return makeResponse(id: id, result: [:])
        case "tools/list":
            return makeResponse(id: id, result: handleToolsList())
        case "tools/call":
            return makeResponse(id: id, result: handleToolsCall(params))
        case "ping":
            return makeResponse(id: id, result: [:])
        default:
            return makeError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Initialize

    private func handleInitialize(_ params: [String: Any]) -> [String: Any] {
        return [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "tools": [:]
            ],
            "serverInfo": [
                "name": "lm-mcp-server",
                "version": "1.0.0"
            ]
        ]
    }

    // MARK: - Tools List

    private func handleToolsList() -> [String: Any] {
        return [
            "tools": [
                makeTool(
                    name: "launchd_list",
                    description: "List macOS launchd services. Returns service labels, status (running/loaded/stopped), PIDs, and domains.",
                    properties: [
                        "domain": ["type": "string", "description": "Domain filter: user, global-agents, global-daemons, system-agents, system-daemons, or all (default: all)"],
                        "status": ["type": "string", "description": "Status filter: running, loaded, stopped, or all (default: all)"],
                        "filter": ["type": "string", "description": "Substring filter on service label"]
                    ],
                    required: []
                ),
                makeTool(
                    name: "launchd_status",
                    description: "Get detailed status of a specific launchd service including PID, exit code, plist path, executable, configuration.",
                    properties: [
                        "label": ["type": "string", "description": "Service label or substring to match"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_start",
                    description: "Start a launchd service. Automatically loads it first if not already loaded.",
                    properties: [
                        "label": ["type": "string", "description": "Service label to start"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_stop",
                    description: "Stop a running launchd service by sending SIGTERM.",
                    properties: [
                        "label": ["type": "string", "description": "Service label to stop"],
                        "force": ["type": "boolean", "description": "Use SIGKILL instead of SIGTERM (default: false)"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_restart",
                    description: "Restart a launchd service (stop then start).",
                    properties: [
                        "label": ["type": "string", "description": "Service label to restart"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_load",
                    description: "Load (bootstrap) a service into launchd so it becomes active.",
                    properties: [
                        "label": ["type": "string", "description": "Service label to load"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_unload",
                    description: "Unload (bootout) a service from launchd.",
                    properties: [
                        "label": ["type": "string", "description": "Service label to unload"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_enable",
                    description: "Enable a service so it auto-loads on boot/login.",
                    properties: [
                        "label": ["type": "string", "description": "Service label to enable"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_disable",
                    description: "Disable a service to prevent it from auto-loading on boot/login.",
                    properties: [
                        "label": ["type": "string", "description": "Service label to disable"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_logs",
                    description: "View logs for a launchd service (stdout, stderr, and system log).",
                    properties: [
                        "label": ["type": "string", "description": "Service label"],
                        "lines": ["type": "integer", "description": "Number of lines to return (default: 50)"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_info",
                    description: "Get raw launchctl print output for a service with full runtime details.",
                    properties: [
                        "label": ["type": "string", "description": "Service label"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_create",
                    description: "Create a new launchd service plist file.",
                    properties: [
                        "label": ["type": "string", "description": "Service label in reverse-DNS format (e.g. com.company.myservice)"],
                        "program": ["type": "string", "description": "Path to the executable"],
                        "domain": ["type": "string", "description": "Domain: user, global-agents, or global-daemons (default: user)"],
                        "arguments": ["type": "array", "items": ["type": "string"], "description": "Program arguments"],
                        "run_at_load": ["type": "boolean", "description": "Start when loaded (default: false)"],
                        "keep_alive": ["type": "boolean", "description": "Restart if it exits (default: false)"],
                        "start_interval": ["type": "integer", "description": "Run every N seconds"],
                        "working_directory": ["type": "string", "description": "Working directory path"],
                        "stdout_path": ["type": "string", "description": "Path for stdout log"],
                        "stderr_path": ["type": "string", "description": "Path for stderr log"],
                        "environment": ["type": "object", "description": "Environment variables as key-value pairs"]
                    ],
                    required: ["label", "program"]
                ),
                makeTool(
                    name: "launchd_delete",
                    description: "Delete a launchd service (unloads it first, then removes the plist file). Cannot delete system-owned services.",
                    properties: [
                        "label": ["type": "string", "description": "Service label to delete"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_plist_read",
                    description: "Read the raw XML plist content of a service.",
                    properties: [
                        "label": ["type": "string", "description": "Service label"]
                    ],
                    required: ["label"]
                ),
                makeTool(
                    name: "launchd_plist_write",
                    description: "Write/update the plist content of a service. Validates XML before saving.",
                    properties: [
                        "label": ["type": "string", "description": "Service label"],
                        "content": ["type": "string", "description": "Full XML plist content to write"]
                    ],
                    required: ["label", "content"]
                )
            ]
        ]
    }

    // MARK: - Tools Call

    private func handleToolsCall(_ params: [String: Any]) -> [String: Any] {
        let toolName = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        let result: String

        switch toolName {
        case "launchd_list":
            result = serviceManager.list(
                domain: arguments["domain"] as? String ?? "all",
                status: arguments["status"] as? String ?? "all",
                filter: arguments["filter"] as? String
            )
        case "launchd_status":
            result = serviceManager.status(label: arguments["label"] as? String ?? "")
        case "launchd_start":
            result = serviceManager.start(label: arguments["label"] as? String ?? "")
        case "launchd_stop":
            result = serviceManager.stop(label: arguments["label"] as? String ?? "", force: arguments["force"] as? Bool ?? false)
        case "launchd_restart":
            result = serviceManager.restart(label: arguments["label"] as? String ?? "")
        case "launchd_load":
            result = serviceManager.load(label: arguments["label"] as? String ?? "")
        case "launchd_unload":
            result = serviceManager.unload(label: arguments["label"] as? String ?? "")
        case "launchd_enable":
            result = serviceManager.enable(label: arguments["label"] as? String ?? "")
        case "launchd_disable":
            result = serviceManager.disable(label: arguments["label"] as? String ?? "")
        case "launchd_logs":
            result = serviceManager.logs(label: arguments["label"] as? String ?? "", lines: arguments["lines"] as? Int ?? 50)
        case "launchd_info":
            result = serviceManager.info(label: arguments["label"] as? String ?? "")
        case "launchd_create":
            result = serviceManager.create(
                label: arguments["label"] as? String ?? "",
                program: arguments["program"] as? String ?? "",
                domain: arguments["domain"] as? String ?? "user",
                arguments: arguments["arguments"] as? [String] ?? [],
                runAtLoad: arguments["run_at_load"] as? Bool ?? false,
                keepAlive: arguments["keep_alive"] as? Bool ?? false,
                startInterval: arguments["start_interval"] as? Int,
                workingDirectory: arguments["working_directory"] as? String,
                stdoutPath: arguments["stdout_path"] as? String,
                stderrPath: arguments["stderr_path"] as? String,
                environment: arguments["environment"] as? [String: String]
            )
        case "launchd_delete":
            result = serviceManager.delete(label: arguments["label"] as? String ?? "")
        case "launchd_plist_read":
            result = serviceManager.plistRead(label: arguments["label"] as? String ?? "")
        case "launchd_plist_write":
            result = serviceManager.plistWrite(label: arguments["label"] as? String ?? "", content: arguments["content"] as? String ?? "")
        default:
            return makeError(id: nil, code: -32602, message: "Unknown tool: \(toolName)")
        }

        return [
            "content": [
                ["type": "text", "text": result]
            ]
        ]
    }

    // MARK: - Helpers

    private func makeTool(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        return [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        ]
    }

    private func makeResponse(id: Any?, result: [String: Any]) -> [String: Any] {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result
        ]
        if let id = id { response["id"] = id }
        return response
    }

    private func makeError(id: Any?, code: Int, message: String) -> [String: Any] {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message
            ]
        ]
        if let id = id { response["id"] = id }
        return response
    }
}
