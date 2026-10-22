import DemoExport
import DemoFixtures
import Foundation

let usage = """
    usage: demo-fixtures export --input <recording.json> --config <DemoConfig.json> --output <DemoFixtures.json>
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.first == "export" else { fail(usage) }
arguments.removeFirst()

var options: [String: String] = [:]
while arguments.count >= 2, arguments[0].hasPrefix("--") {
    options[String(arguments[0].dropFirst(2))] = arguments[1]
    arguments.removeFirst(2)
}
guard arguments.isEmpty, let input = options["input"], let configPath = options["config"],
      let output = options["output"] else { fail(usage) }

do {
    let recording = try DemoRecording.decode(from: Data(contentsOf: URL(fileURLWithPath: input)))
    let config = try DemoConfig.decode(from: Data(contentsOf: URL(fileURLWithPath: configPath)))
    let exporter = DemoExporter(config: config)
    let archive = try exporter.export(recording)
    let data = try exporter.encode(archive, recording: recording)
    print("Leak check passed: no real character id, corporation or alliance id, pilot name, owner hash or token.")
    try data.write(to: URL(fileURLWithPath: output), options: .atomic)
    print("\(archive.entries.count) entries, \(archive.names.count) names, \(data.count) bytes → \(output)")
} catch {
    fail("error: \(error)")
}
