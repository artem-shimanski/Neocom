//
//  CheckSDEVersion.swift
//  SDE
//

import PackagePlugin

/// Checks that `Data/sde.sqlite` of the target was built from the SDE that DogmaKit was imported from.
///
/// The command produces a Swift source compiled into the target, so it runs in every build; it reruns
/// when the database or the tool (and so `DogmaIDs.SDEVersion`) changes.
@main
struct CheckSDEVersionPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let database = target.directoryURL.appending(path: "Data/sde.sqlite")
        let output = context.pluginWorkDirectoryURL.appending(path: "SDEVersionCheck.swift")
        return [
            .buildCommand(
                displayName: "Checking SDE build of \(target.name)",
                executable: try context.tool(named: "SDEVersionCheck").url,
                arguments: [database.path(percentEncoded: false), output.path(percentEncoded: false)],
                inputFiles: [database],
                outputFiles: [output]
            )
        ]
    }
}
