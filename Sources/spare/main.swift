import Foundation
import SpareCLI
import SpareCore

let variables = ProcessInfo.processInfo.environment
let home = variables["SPARE_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser
let supportDirectory = SpareEnvironment.live(home: home).supportDirectory
let settings = SettingsStore(directory: supportDirectory).load(home: home.resolvingSymlinksInPath())
var environment = SpareEnvironment.live(home: home, settings: settings)
// QA only: send trashed items to a plain folder instead of the real Trash (`FileManager.trashItem` ignores
// SPARE_HOME): `SPARE_TRASH_DIR`, or `<SPARE_HOME>/.Trash` when only SPARE_HOME is set.
if let trashFolder = TrashFolder.override(variables: variables, home: home) {
    environment.trash = DirectoryTrash(folder: trashFolder)
}
let cli = SpareCLI(environment: environment, write: { print($0) },
    writeError: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
let code = await cli.run(Array(CommandLine.arguments.dropFirst()))
exit(code)
