import SwiftUI

enum DepotColor {
    static let canvas = Color(red: 7 / 255, green: 7 / 255, blue: 8 / 255)
    static let bg = Color(red: 11 / 255, green: 12 / 255, blue: 14 / 255)
    static let elevated = Color(red: 22 / 255, green: 23 / 255, blue: 26 / 255)
    static let fg = Color(red: 232 / 255, green: 226 / 255, blue: 214 / 255)
    static let muted = Color(red: 163 / 255, green: 158 / 255, blue: 148 / 255)
    static let subtle = Color(red: 111 / 255, green: 106 / 255, blue: 98 / 255)
    static let line = Color(red: 44 / 255, green: 43 / 255, blue: 40 / 255)
    static let ok = Color(red: 126 / 255, green: 168 / 255, blue: 146 / 255)
    static let danger = Color(red: 196 / 255, green: 107 / 255, blue: 90 / 255)
}

struct Profile: Equatable {
    let login: String
    let name: String
    let avatarURL: URL?
    let bio: String
    let publicRepos: Int
}

struct Repo: Identifiable, Hashable {
    let id: Int
    let owner: String
    let name: String
    let fullName: String
    let blurb: String
    let language: String
    let stars: Int
    let forks: Int
    let updatedAt: String
    let htmlURL: String
    let defaultBranch: String
    let isPrivate: Bool
    let isFork: Bool
    let avatarURL: URL?
}

struct ReleaseItem: Identifiable, Hashable {
    let id: Int
    let tag: String
    let name: String
    let body: String
    let publishedAt: String
    let isPrerelease: Bool
    let htmlURL: String
    let author: String
}

struct GHCommit: Identifiable, Hashable {
    var id: String { sha }
    let sha: String
    let title: String
    let body: String
    let date: String
    let authorName: String
    let authorLogin: String
    let htmlURL: String
}

struct CommitFile: Identifiable, Hashable {
    var id: String { filename }
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let patch: String
}

struct CommitDetail: Hashable {
    let commit: GHCommit
    let additions: Int
    let deletions: Int
    let files: [CommitFile]
}

struct ActionRun: Identifiable, Hashable {
    let id: Int
    let name: String
    let title: String
    let status: String
    let conclusion: String
    let branch: String
    let htmlURL: String
    let createdAt: String
}

enum GitHubJSON {
    static func dict(_ any: Any?) -> [String: Any] {
        any as? [String: Any] ?? [:]
    }

    static func string(_ object: [String: Any], _ key: String) -> String {
        object[key] as? String ?? ""
    }

    static func int(_ object: [String: Any], _ key: String) -> Int {
        if let value = object[key] as? Int { return value }
        if let value = object[key] as? NSNumber { return value.intValue }
        return 0
    }

    static func bool(_ object: [String: Any], _ key: String) -> Bool {
        if let value = object[key] as? Bool { return value }
        if let value = object[key] as? NSNumber { return value.boolValue }
        return false
    }

    static func profile(_ any: Any?) -> Profile? {
        let object = dict(any)
        let login = string(object, "login")
        guard !login.isEmpty else { return nil }
        let name = string(object, "name")
        return Profile(
            login: login,
            name: name.isEmpty ? login : name,
            avatarURL: URL(string: string(object, "avatar_url")),
            bio: string(object, "bio"),
            publicRepos: int(object, "public_repos")
        )
    }

    static func repo(_ any: Any?) -> Repo? {
        let object = dict(any)
        let owner = dict(object["owner"])
        let login = string(owner, "login")
        let name = string(object, "name")
        guard !login.isEmpty, !name.isEmpty else { return nil }
        let full = string(object, "full_name")
        return Repo(
            id: int(object, "id"),
            owner: login,
            name: name,
            fullName: full.isEmpty ? "\(login)/\(name)" : full,
            blurb: string(object, "description"),
            language: string(object, "language"),
            stars: int(object, "stargazers_count"),
            forks: int(object, "forks_count"),
            updatedAt: string(object, "updated_at"),
            htmlURL: string(object, "html_url"),
            defaultBranch: {
                let branch = string(object, "default_branch")
                return branch.isEmpty ? "main" : branch
            }(),
            isPrivate: bool(object, "private"),
            isFork: bool(object, "fork"),
            avatarURL: URL(string: string(owner, "avatar_url"))
        )
    }

    static func repos(_ any: Any?) -> [Repo] {
        let list: [Any]
        if let array = any as? [Any] {
            list = array
        } else {
            list = dict(any)["items"] as? [Any] ?? []
        }
        return list.compactMap { repo($0) }
    }

    static func release(_ any: Any?) -> ReleaseItem? {
        let object = dict(any)
        let tag = string(object, "tag_name")
        guard !tag.isEmpty else { return nil }
        let name = string(object, "name")
        return ReleaseItem(
            id: int(object, "id"),
            tag: tag,
            name: name.isEmpty ? tag : name,
            body: string(object, "body"),
            publishedAt: string(object, "published_at"),
            isPrerelease: bool(object, "prerelease"),
            htmlURL: string(object, "html_url"),
            author: string(dict(object["author"]), "login")
        )
    }

    static func commit(_ any: Any?) -> GHCommit? {
        let object = dict(any)
        let sha = string(object, "sha")
        guard !sha.isEmpty else { return nil }
        let commit = dict(object["commit"])
        let message = string(commit, "message")
        let lines = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map { String($0) }
        let title = (lines.first ?? "").isEmpty ? String(sha.prefix(7)) : lines[0]
        let body = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let gitAuthor = dict(commit["author"])
        let user = dict(object["author"])
        return GHCommit(
            sha: sha,
            title: title,
            body: body,
            date: string(gitAuthor, "date"),
            authorName: string(gitAuthor, "name"),
            authorLogin: string(user, "login"),
            htmlURL: string(object, "html_url")
        )
    }

    static func commitDetail(_ any: Any?) -> CommitDetail? {
        guard let commit = commit(any) else { return nil }
        let object = dict(any)
        let stats = dict(object["stats"])
        let files = (object["files"] as? [Any] ?? []).compactMap { item -> CommitFile? in
            let file = dict(item)
            let name = string(file, "filename")
            guard !name.isEmpty else { return nil }
            return CommitFile(
                filename: name,
                status: string(file, "status"),
                additions: int(file, "additions"),
                deletions: int(file, "deletions"),
                patch: string(file, "patch")
            )
        }
        return CommitDetail(
            commit: commit,
            additions: int(stats, "additions"),
            deletions: int(stats, "deletions"),
            files: files
        )
    }

    static func run(_ any: Any?) -> ActionRun? {
        let object = dict(any)
        let id = int(object, "id")
        guard id != 0 else { return nil }
        let name = string(object, "name")
        return ActionRun(
            id: id,
            name: name.isEmpty ? "Workflow" : name,
            title: string(object, "display_title"),
            status: string(object, "status"),
            conclusion: string(object, "conclusion"),
            branch: string(object, "head_branch"),
            htmlURL: string(object, "html_url"),
            createdAt: string(object, "created_at")
        )
    }
}

enum DepotFormat {
    static func ago(_ iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else { return "" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 30 { return "\(days)d" }
        let months = days / 30
        if months < 12 { return "\(months)mo" }
        return "\(months / 12)y"
    }

    static func compact(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000).replacingOccurrences(of: ".0", with: "")
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000).replacingOccurrences(of: ".0", with: "")
        }
        return "\(value)"
    }

    static func shortSHA(_ sha: String) -> String {
        String(sha.prefix(7))
    }
}
