import Foundation

/// Finder Sync knows the selection's paths but does not receive read access.
/// Pass a command URL, not document URLs: Launch Services otherwise rejects
/// the handoff before the host can present its folder authorization panel.
nonisolated enum FinderSendRequest {
    static let scheme = "airfliq"

    static func encode(_ files: [URL]) -> URL? {
        guard !files.isEmpty, files.allSatisfy(isLocalFile) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "send"
        components.path = "/v1"
        components.queryItems = files.map { URLQueryItem(name: "file", value: $0.absoluteString) }
        return components.url
    }

    static func decode(_ request: URL) -> [URL]? {
        guard let components = URLComponents(url: request, resolvingAgainstBaseURL: false),
              components.scheme == scheme, components.host == "send",
              components.path == "/v1", components.user == nil,
              components.password == nil, components.port == nil,
              components.fragment == nil,
              let items = components.queryItems, !items.isEmpty else { return nil }
        var files: [URL] = []
        for item in items {
            guard item.name == "file", let value = item.value, !value.contains("\0"),
                  let file = URL(string: value), isLocalFile(file) else { return nil }
            files.append(file)
        }
        return files
    }

    private static func isLocalFile(_ url: URL) -> Bool {
        url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
            && url.path.hasPrefix("/") && !url.path.contains("\0")
            && url.query == nil && url.fragment == nil
    }
}
