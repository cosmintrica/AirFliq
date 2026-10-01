import Foundation

@main struct FinderSendRequestTests {
    static func main() {
        let files = [
            URL(fileURLWithPath: "/Users/test/Movies/clip.MP4"),
            URL(fileURLWithPath: "/Users/test/Poze/ședință #1 & 20% + ?.png"),
            URL(fileURLWithPath: "/Users/test/A folder", isDirectory: true)
        ]
        let request = FinderSendRequest.encode(files)!
        precondition(!request.isFileURL)
        precondition(FinderSendRequest.decode(request) == files)
        precondition(FinderSendRequest.decode(request)!.last!.hasDirectoryPath)
        precondition(FinderSendRequest.encode([]) == nil)
        precondition(FinderSendRequest.encode([URL(string: "https://example.com/file")!]) == nil)
        precondition(FinderSendRequest.encode([URL(string: "file://remote/shared/file")!]) == nil)
        for invalid in [
            "airfliq://send/v1", "airfliq://send/v2?file=file:///tmp/a",
            "other://send/v1?file=file:///tmp/a", "airfliq://other/v1?file=file:///tmp/a",
            "airfliq://user@send/v1?file=file:///tmp/a", "airfliq://send:42/v1?file=file:///tmp/a",
            "airfliq://send/v1?file=https://example.com/a", "airfliq://send/v1?file=file://remote/a",
            "airfliq://send/v1?file=file:///tmp/a&file=relative", "airfliq://send/v1?wrong=file:///tmp/a",
            "airfliq://send/v1?file=file:///tmp/a#fragment", "airfliq://send/v1?file=file:///tmp/a%00b"
        ] {
            precondition(FinderSendRequest.decode(URL(string: invalid)!) == nil, invalid)
        }
        let many = (0..<1000).map { URL(fileURLWithPath: "/tmp/multi/file \($0).txt") }
        precondition(FinderSendRequest.decode(FinderSendRequest.encode(many)!) == many)
        print("PASS: Finder selection round trip, Unicode, reserved characters, folders, 1000 items and invalid requests")
    }
}
