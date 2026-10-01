import Foundation

/// One pending send keeps its original files while the user authorizes the
/// missing folders. All dependencies are injectable to test retries/cancellation.
@MainActor
final class FolderAccessRequest {
    typealias ChooseFolder = (URL, Int, Bool, @escaping (URL?) -> Void) -> Void

    private var remaining: [URL]
    private let forceAuthorization: Bool
    private let isReadable: (URL) -> Bool
    private let fileExists: (URL) -> Bool
    private let reportUnavailable: (URL) -> Void
    private let chooseFolder: ChooseFolder
    private let rememberFolder: (URL) -> Void
    private let completion: (Bool) -> Void
    private var finished = false

    init(urls: [URL], forceAuthorization: Bool = false,
         isReadable: @escaping (URL) -> Bool,
         fileExists: @escaping (URL) -> Bool,
         reportUnavailable: @escaping (URL) -> Void,
         chooseFolder: @escaping ChooseFolder,
         rememberFolder: @escaping (URL) -> Void,
         completion: @escaping (Bool) -> Void) {
        self.remaining = urls
        self.forceAuthorization = forceAuthorization
        self.isReadable = isReadable
        self.fileExists = fileExists
        self.reportUnavailable = reportUnavailable
        self.chooseFolder = chooseFolder
        self.rememberFolder = rememberFolder
        self.completion = completion
    }

    func start() {
        if !forceAuthorization { remaining.removeAll(where: isReadable) }
        advance()
    }

    private func advance(retry: Bool = false) {
        guard !finished else { return }
        guard let item = remaining.first else { finish(true); return }
        let folder = Self.suggestedFolder(for: item)
        chooseFolder(folder, remaining.count, retry) { [self] selected in
            guard !finished else { return }
            guard let selected else { finish(false); return }
            // Do not persist an unrelated folder just because it was picked.
            guard remaining.contains(where: { Self.contains(selected, item: $0) }) else {
                advance(retry: true)
                return
            }
            rememberFolder(selected)
            if isReadable(selected), let missing = remaining.first(where: {
                Self.contains(selected, item: $0) && !fileExists($0)
            }) {
                reportUnavailable(missing)
                finish(false)
                return
            }
            let previousCount = remaining.count
            remaining.removeAll {
                isReadable($0) && (!forceAuthorization || Self.contains(selected, item: $0))
            }
            advance(retry: remaining.count == previousCount)
        }
    }

    private func finish(_ granted: Bool) {
        guard !finished else { return }
        finished = true
        completion(granted)
    }

    static func suggestedFolder(for item: URL) -> URL {
        if item.hasDirectoryPath || (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return item.standardizedFileURL
        }
        return item.deletingLastPathComponent().standardizedFileURL
    }

    static func contains(_ folder: URL, item: URL) -> Bool {
        let components = folder.standardizedFileURL.pathComponents
        return item.standardizedFileURL.pathComponents.starts(with: components)
    }
}

/// Sharing services can discover a sandbox denial after the initial file check.
nonisolated enum FileAccessFailure {
    static func isPermissionError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        for _ in 0..<8 {
            guard let candidate = current else { return false }
            if candidate.domain == NSCocoaErrorDomain && candidate.code == NSFileReadNoPermissionError {
                return true
            }
            if candidate.domain == NSPOSIXErrorDomain && [1, 13].contains(candidate.code) { return true }
            if candidate.domain == NSOSStatusErrorDomain && candidate.code == -54 { return true }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
