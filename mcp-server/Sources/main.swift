import Foundation

// MCP Server for Launch Manager
// Implements the Model Context Protocol over stdio (JSON-RPC 2.0)

let server = MCPServer()
server.run()
