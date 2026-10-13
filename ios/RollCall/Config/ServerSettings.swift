//
//  ServerSettings.swift
//  RollCall
//
//  Which RollCall server the app talks to.
//
//    This Mac       http://localhost:8000, the server running on the same
//                   Mac as the simulator (the default).
//    Shared server  a web address someone else gave you, e.g. Sujan's Mac
//                   shared through a Cloudflare tunnel
//                   (https://something.trycloudflare.com). Everyone using the
//                   same shared server sees the same accounts and data.
//
//  The choice is saved on the device. (Debug tip: launch with
//  "-RCServerURL http://localhost:8000" to force a server, as the UI tests do.)
//

import Foundation

enum ServerSettings {
    static let thisMac = URL(string: "http://localhost:8000")!
    private static let key = "RCServerURL"

    /// The server the app uses right now.
    static var url: URL {
        UserDefaults.standard.string(forKey: key).flatMap(URL.init(string:)) ?? thisMac
    }

    static var isThisMac: Bool { url == thisMac }

    /// Save a shared server's address, or nil to go back to this Mac.
    static func use(_ url: URL?) {
        if let url, url != thisMac {
            UserDefaults.standard.set(url.absoluteString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Turn what someone typed or pasted into a server address:
    /// "abc.trycloudflare.com/" -> https://abc.trycloudflare.com
    static func address(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        return url
    }

    /// A short name for the screen: "This Mac" or "abc.trycloudflare.com".
    static func displayName(for url: URL) -> String {
        url == thisMac ? String(localized: "This Mac") : (url.host() ?? url.absoluteString)
    }
}
