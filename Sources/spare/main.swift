import Foundation
import SpareCLI
import SpareCore

let variables = ProcessInfo.processInfo.environment
let home = variables["SPARE_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser
let cli = SpareCLI(environment: .live(home: home), write: { print($0) })
let code = await cli.run(Array(CommandLine.arguments.dropFirst()))
exit(code)
