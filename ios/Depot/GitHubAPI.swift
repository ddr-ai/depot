import Foundation

struct GHError: LocalizedError {
    let message: String
    let status: Int
    var errorDescription: String? { message }
}

struct GHResponse {
    let status: Int
    let json: Any?
    let text: String
}

@MainActor
final class GitHubAPI {
    var token = ""

    func profile() async throws -> Profile {
        let response = try await send("/user")
        guard let profile = GitHubJSON.profile(response.json) else {
            throw GHError(message: "Couldn't read your GitHub profile.", status: response.status)
        }
        return profile
    }

    func myRepos(page: Int) async throws -> [Repo] {
        let response = try await send(
            "/user/repos?per_page=30&page=\(page)&sort=updated&direction=desc&affiliation=owner,collaborator,organization_member"
        )
        return GitHubJSON.repos(response.json)
    }

    func search(query: String, page: Int) async throws -> [Repo] {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "sort", value: "stars"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "30"),
            URLQueryItem(name: "page", value: "\(page)"),
        ]
        let queryString = components.percentEncodedQuery ?? ""
        let response = try await send("/search/repositories?\(queryString)")
        return GitHubJSON.repos(response.json)
    }

    func starred(page: Int) async throws -> [Repo] {
        let response = try await send("/user/starred?per_page=30&page=\(page)&sort=created&direction=desc")
        return GitHubJSON.repos(response.json)
    }

    func repo(owner: String, name: String) async throws -> Repo {
        let response = try await send("/repos/\(seg(owner))/\(seg(name))")
        guard let repo = GitHubJSON.repo(response.json) else {
            throw GHError(message: "Couldn't read that repository.", status: response.status)
        }
        return repo
    }

    func readme(owner: String, name: String) async throws -> String {
        do {
            let response = try await send("/repos/\(seg(owner))/\(seg(name))/readme", raw: true)
            return response.text
        } catch let error as GHError where error.status == 404 {
            return ""
        }
    }

    func releases(owner: String, name: String) async throws -> [ReleaseItem] {
        let response = try await send("/repos/\(seg(owner))/\(seg(name))/releases?per_page=20")
        return (response.json as? [Any] ?? []).compactMap { GitHubJSON.release($0) }
    }

    func commits(owner: String, name: String, page: Int) async throws -> [GHCommit] {
        let response = try await send("/repos/\(seg(owner))/\(seg(name))/commits?per_page=30&page=\(page)")
        return (response.json as? [Any] ?? []).compactMap { GitHubJSON.commit($0) }
    }

    func commit(owner: String, name: String, sha: String) async throws -> CommitDetail {
        let response = try await send("/repos/\(seg(owner))/\(seg(name))/commits/\(seg(sha))")
        guard let detail = GitHubJSON.commitDetail(response.json) else {
            throw GHError(message: "Couldn't read that commit.", status: response.status)
        }
        return detail
    }

    func actions(owner: String, name: String) async throws -> [ActionRun] {
        do {
            let response = try await send("/repos/\(seg(owner))/\(seg(name))/actions/runs?per_page=20")
            let runs = GitHubJSON.dict(response.json)["workflow_runs"] as? [Any] ?? []
            return runs.compactMap { GitHubJSON.run($0) }
        } catch let error as GHError where error.status == 404 {
            return []
        }
    }

    func isStarred(owner: String, name: String) async throws -> Bool {
        do {
            let response = try await send("/user/starred/\(seg(owner))/\(seg(name))")
            return response.status == 204
        } catch let error as GHError where error.status == 404 {
            return false
        }
    }

    func setStar(owner: String, name: String, starred: Bool) async throws {
        _ = try await send("/user/starred/\(seg(owner))/\(seg(name))", method: starred ? "PUT" : "DELETE")
    }

    func createRepo(name: String, description: String, isPrivate: Bool, readme: Bool) async throws -> Repo {
        let response = try await send(
            "/user/repos",
            method: "POST",
            json: [
                "name": name,
                "description": description,
                "private": isPrivate,
                "auto_init": readme,
            ]
        )
        guard let repo = GitHubJSON.repo(response.json) else {
            throw GHError(message: "Repository created, but the response was unreadable.", status: response.status)
        }
        return repo
    }

    func deleteRepo(owner: String, name: String) async throws {
        do {
            _ = try await send("/repos/\(seg(owner))/\(seg(name))", method: "DELETE")
        } catch let error as GHError where error.status == 403 {
            throw GHError(
                message: "GitHub refused the delete. The token needs the delete_repo scope, or administration on this repo.",
                status: 403
            )
        }
    }

    private func seg(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func send(
        _ path: String,
        method: String = "GET",
        json: [String: Any]? = nil,
        raw: Bool = false
    ) async throws -> GHResponse {
        guard let url = URL(string: "https://api.github.com" + path) else {
            throw GHError(message: "Bad GitHub URL.", status: 0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Depot", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(raw ? "application/vnd.github.raw" : "application/vnd.github+json", forHTTPHeaderField: "Accept")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GHError(message: "Couldn't reach GitHub. Try again.", status: 0)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 204 {
            return GHResponse(status: status, json: nil, text: "")
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        if raw, (200..<300).contains(status) {
            return GHResponse(status: status, json: nil, text: text)
        }
        let object = (try? JSONSerialization.jsonObject(with: data))
        guard (200..<300).contains(status) else {
            throw GHError(message: message(from: object, status: status), status: status)
        }
        return GHResponse(status: status, json: object, text: text)
    }

    private func message(from object: Any?, status: Int) -> String {
        let raw = GitHubJSON.string(GitHubJSON.dict(object), "message")
        if status == 401 {
            return "GitHub rejected that token. Check it in Account."
        }
        if status == 429 || raw.localizedCaseInsensitiveContains("rate limit") {
            return "GitHub rate limit reached. Add a token in Account to keep going."
        }
        if status == 404 {
            return raw.isEmpty ? "Not found. It may be private, or already gone." : raw
        }
        if status == 403 {
            return raw.isEmpty ? "GitHub refused this request. A token with the right scopes may be required." : raw
        }
        if status == 422 {
            let errors = GitHubJSON.dict(object)["errors"] as? [[String: Any]] ?? []
            let detail = errors.compactMap { $0["message"] as? String }.joined(separator: " ")
            if !detail.isEmpty { return detail }
            return raw.isEmpty ? "GitHub could not accept that." : raw
        }
        if raw.isEmpty { return "GitHub request failed (\(status))." }
        return raw
    }
}
