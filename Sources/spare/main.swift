import Foundation
import SpareCLI
import SpareCore

let variables = ProcessInfo.processInfo.environment
let home = variables["SPARE_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser
var environment = SpareEnvironment.live(home: home)
// QA only: send trashed items to a plain folder instead of the real Trash (`FileManager.trashItem` ignores SPARE_HOME).
if let trashFolder = variables["SPARE_TRASH_DIR"] {
    environment.trash = DirectoryTrash(folder: URL(fileURLWithPath: trashFolder, isDirectory: true))
}
let cli = SpareCLI(environment: environment, write: { print($0) },
    writeError: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
let code = await cli.run(Array(CommandLine.arguments.dropFirst()))
exit(code)
