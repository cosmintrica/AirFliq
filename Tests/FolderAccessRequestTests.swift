import Foundation

@main
struct FolderAccessRequestTests {
    @MainActor static func main() {
        let a = URL(fileURLWithPath: "/example/a/report.txt")
        let b = URL(fileURLWithPath: "/example/b/photo.png")
        let folderA = a.deletingLastPathComponent()
        let folderB = b.deletingLastPathComponent()
        let root = folderA.deletingLastPathComponent()
        var grants: [URL] = []
        var prompts: [(URL, Bool)] = []
        var answer: ((URL?) -> Void)?
        var results: [Bool] = []
        func readable(_ url: URL) -> Bool {
            grants.contains { FolderAccessRequest.contains($0, item: url) }
        }
        func request(_ urls: [URL], forced: Bool = false) -> FolderAccessRequest {
            FolderAccessRequest(urls: urls, forceAuthorization: forced,
                isReadable: readable,
                fileExists: { _ in true }, reportUnavailable: { _ in preconditionFailure() },
                chooseFolder: { folder, _, retry, completion in
                    prompts.append((folder, retry)); answer = completion
                }, rememberFolder: { grants.append($0) },
                completion: { results.append($0) })
        }
        let multi = request([a, b])
        multi.start()
        precondition(prompts.count == 1 && prompts[0].0 == folderA && results.isEmpty)
        answer?(folderA)
        precondition(prompts.count == 2 && prompts[1].0 == folderB && results.isEmpty)
        answer?(folderB)
        precondition(results == [true] && grants.count == 2)
        print("PASS: two missing folders prompt in order; one completion after both")

        results = []; prompts = []
        let reused = request([a, b]); reused.start()
        precondition(results == [true] && prompts.isEmpty)
        print("PASS: existing access skips prompts")

        grants = []; prompts = []; results = []
        let parent = request([a, b]); parent.start(); answer?(root)
        precondition(prompts.count == 1 && results == [true])
        print("PASS: explicitly choosing a shared parent resolves all covered files")

        grants = []; prompts = []; results = []
        let wrong = request([a]); wrong.start()
        answer?(URL(fileURLWithPath: "/example/another"))
        precondition(grants.isEmpty && prompts.count == 2 && prompts[1].1 && results.isEmpty)
        answer?(folderA)
        precondition(results == [true])
        print("PASS: unrelated folder is not saved; user can correct it")

        grants = []; prompts = []; results = []
        let cancel = request([a,b]); cancel.start(); answer?(folderA); answer?(nil)
        precondition(results == [false] && grants == [folderA])
        print("PASS: cancelling the second folder cancels the whole pending send")

        grants = [root]; prompts = []; results = []
        let forced = request([a], forced: true); forced.start()
        precondition(prompts.count == 1 && results.isEmpty)
        answer?(folderA)
        precondition(results == [true])
        print("PASS: late sharing-service denial asks again even if preflight was readable")

        precondition(!FolderAccessRequest.contains(folderA, item: URL(fileURLWithPath: "/example/abc/file")))
        precondition(FolderAccessRequest.contains(folderA, item: a))
        precondition(FolderAccessRequest.suggestedFolder(for: URL(fileURLWithPath: "/example/folder", isDirectory: true)).path == "/example/folder")
        print("PASS: directory suggestions and path boundaries")

        results = []; prompts = []
        var reportedMissing = false
        let missing = FolderAccessRequest(urls: [a],
            isReadable: { $0 == folderA }, fileExists: { _ in false },
            reportUnavailable: { _ in reportedMissing = true },
            chooseFolder: { _, _, _, completion in answer = completion },
            rememberFolder: { _ in }, completion: { results.append($0) })
        missing.start(); answer?(folderA)
        precondition(reportedMissing && results == [false])
        print("PASS: missing file after authorization reports failure without a prompt loop")

        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        let wrapped = NSError(domain: "Sharing", code: 1, userInfo: [NSUnderlyingErrorKey: denied])
        precondition(FileAccessFailure.isPermissionError(denied))
        precondition(FileAccessFailure.isPermissionError(wrapped))
        precondition(FileAccessFailure.isPermissionError(NSError(domain: NSPOSIXErrorDomain, code: 13)))
        precondition(!FileAccessFailure.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        precondition(!FileAccessFailure.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)))
        print("PASS: only permission failures trigger automatic recovery")
    }
}
