import Foundation
import Security

/// Handles privileged operations using Authorization Services
class PrivilegedHelper {
    static let shared = PrivilegedHelper()

    private var authRef: AuthorizationRef?

    private init() {}

    /// Request authorization from the user
    func authorize() -> Bool {
        if authRef != nil { return true }

        var auth: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &auth)

        guard status == errAuthorizationSuccess, let authorization = auth else {
            return false
        }

        authRef = authorization
        return true
    }

    /// Run a command with elevated privileges
    func runWithPrivileges(command: String, arguments: [String], completion: @escaping (String) -> Void) {
        guard authorize() else {
            completion("Error: Failed to obtain authorization")
            return
        }

        // Use AppleScript to run with admin privileges as a fallback
        // since AuthorizationExecuteWithPrivileges is deprecated
        let escapedArgs = arguments.map { arg in
            arg.replacingOccurrences(of: "\\", with: "\\\\")
               .replacingOccurrences(of: "\"", with: "\\\"")
        }

        let argString = escapedArgs.map { "\"\($0)\"" }.joined(separator: " ")
        let script = """
        do shell script "\(command) \(argString)" with administrator privileges
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            let result = appleScript?.executeAndReturnError(&error)

            DispatchQueue.main.async {
                if let error = error {
                    let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    completion("Error: \(errorMsg)")
                } else {
                    completion(result?.stringValue ?? "")
                }
            }
        }
    }

    /// Release authorization
    func deauthorize() {
        if let auth = authRef {
            AuthorizationFree(auth, [.destroyRights])
            authRef = nil
        }
    }

    deinit {
        deauthorize()
    }
}
