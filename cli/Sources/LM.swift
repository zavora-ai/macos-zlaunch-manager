import ArgumentParser
import Foundation

@main
struct LM: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lm",
        abstract: "Launch Manager — macOS launchd service manager",
        version: "1.1.0",
        subcommands: [
            List.self,
            Status.self,
            Start.self,
            Stop.self,
            Restart.self,
            Load.self,
            Unload.self,
            Enable.self,
            Disable.self,
            Logs.self,
            Info.self,
            Create.self,
            Delete.self,
            Edit.self,
            GUI.self,
        ],
        defaultSubcommand: List.self
    )
}
