import Foundation
import Testing
@testable import SpareCore

@Suite struct SystemTrashTests {
    func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test func acceptsVolumeTrashesOfTheCurrentUser() {
        #expect(SystemTrash.isVolumeTrashChild(url("/.Trashes/501/old.dmg"), uid: 501))
        #expect(SystemTrash.isVolumeTrashChild(url("/Volumes/Backup/.Trashes/501/old.dmg"), uid: 501))
    }

    @Test func rejectsOtherUsersAndOtherShapes() {
        #expect(!SystemTrash.isVolumeTrashChild(url("/.Trashes/502/old.dmg"), uid: 501))
        #expect(!SystemTrash.isVolumeTrashChild(url("/.Trashes/old.dmg"), uid: 501))
        #expect(!SystemTrash.isVolumeTrashChild(url("/.Trashes/501"), uid: 501))
        #expect(!SystemTrash.isVolumeTrashChild(url("/.Trashes/501/sub/old.dmg"), uid: 501))
        #expect(!SystemTrash.isVolumeTrashChild(url("/Users/me/.Trashes/501/old.dmg"), uid: 501))
        #expect(!SystemTrash.isVolumeTrashChild(url("/Volumes/Backup/data/.Trashes/501/old.dmg"), uid: 501))
        #expect(!SystemTrash.isVolumeTrashChild(url("/Volumes/.Trashes/501/old.dmg"), uid: 501))
        #expect(!SystemTrash.isVolumeTrashChild(url("/.Trashes/5010/old.dmg"), uid: 501))
    }
}
