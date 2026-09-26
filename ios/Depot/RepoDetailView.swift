import SwiftUI
import UIKit

struct RepoDetailView: View {
    let repo: Repo
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: Session

    @State private var live: Repo?
    @State private var tab = 0
    @State private var readme = ""
    @State private var releases: [ReleaseItem] = []
    @State private var commits: [GHCommit] = []
    @State private var runs: [ActionRun] = []
    @State private var starred = false
    @State private var starKnown = false
    @State private var error: String?
    @State private var loading = false
    @State private var copied = false
    @State private var confirmDelete = false
    @State private var commitPage = 1
    @State private var moreCommits = false

    private var shown: Repo { live ?? repo }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("Section", selection: $tab) {
                    Text("Readme").tag(0)
                    Text("Releases").tag(1)
                    Text("Commits").tag(2)
                    Text("Actions").tag(3)
                }
                .pickerStyle(.segmented)

                if let error {
                    Text(error)
                        .font(.custom("Avenir Next", size: 15))
                        .foregroundStyle(DepotColor.danger)
                } else if loading && contentIsEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    content
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(DepotColor.bg)
        .navigationTitle(shown.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: tab) { await loadTab() }
        .task { await loadMeta() }
        .confirmationDialog(
            "Delete \(shown.fullName)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete repository", role: .destructive) {
                Task { await deleteRepo() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var contentIsEmpty: Bool {
        switch tab {
        case 1: return releases.isEmpty
        case 2: return commits.isEmpty
        case 3: return runs.isEmpty
        default: return readme.isEmpty
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shown.fullName)
                .font(.custom("Avenir Next", size: 13))
                .foregroundStyle(DepotColor.subtle)
            if !shown.blurb.isEmpty {
                Text(shown.blurb)
                    .font(.custom("Avenir Next", size: 16))
                    .foregroundStyle(DepotColor.fg)
            }
            HStack(spacing: 14) {
                Label(DepotFormat.compact(shown.stars), systemImage: "star")
                Label(DepotFormat.compact(shown.forks), systemImage: "arrow.triangle.branch")
                if !shown.language.isEmpty {
                    Text(shown.language)
                }
                if shown.isPrivate {
                    Label("Private", systemImage: "lock")
                }
            }
            .font(.custom("Avenir Next", size: 13))
            .foregroundStyle(DepotColor.muted)

            HStack(spacing: 8) {
                Button {
                    Task { await toggleStar() }
                } label: {
                    Label(starred ? "Starred" : "Star", systemImage: starred ? "star.fill" : "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DepotButtonStyle(filled: starred))
                .disabled(!starKnown)

                Button {
                    UIPasteboard.general.string = shown.htmlURL
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Clone URL", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DepotButtonStyle(filled: false))

                if let url = URL(string: shown.htmlURL) {
                    Link(destination: url) {
                        Image(systemName: "safari")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(DepotButtonStyle(filled: false))
                }
            }

            if session.profile?.login.lowercased() == shown.owner.lowercased() {
                Button("Delete repository", role: .destructive) {
                    confirmDelete = true
                }
                .font(.custom("Avenir Next", size: 14))
                .foregroundStyle(DepotColor.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case 1:
            if releases.isEmpty {
                Text("No releases.").foregroundStyle(DepotColor.subtle)
            } else {
                ForEach(releases) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.tag)
                                .font(.custom("Avenir Next", size: 16).weight(.medium))
                            if item.isPrerelease {
                                Text("pre")
                                    .font(.custom("Avenir Next", size: 11))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DepotColor.elevated)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Text(DepotFormat.ago(item.publishedAt))
                                .foregroundStyle(DepotColor.subtle)
                        }
                        if item.name != item.tag {
                            Text(item.name).foregroundStyle(DepotColor.muted)
                        }
                        if !item.body.isEmpty {
                            Text(item.body).lineLimit(6).foregroundStyle(DepotColor.fg)
                        }
                    }
                    .font(.custom("Avenir Next", size: 14))
                    .padding(.vertical, 8)
                    Divider().overlay(DepotColor.line)
                }
            }
        case 2:
            if commits.isEmpty {
                Text("No commits.").foregroundStyle(DepotColor.subtle)
            } else {
                ForEach(commits) { commit in
                    NavigationLink {
                        CommitScreen(owner: shown.owner, name: shown.name, sha: commit.sha, preview: commit)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(commit.title)
                                .font(.custom("Avenir Next", size: 16))
                                .foregroundStyle(DepotColor.fg)
                                .multilineTextAlignment(.leading)
                            HStack {
                                Text(commit.authorLogin.isEmpty ? commit.authorName : commit.authorLogin)
                                Text(DepotFormat.shortSHA(commit.sha))
                                    .font(.custom("Menlo", size: 12))
                                Spacer()
                                Text(DepotFormat.ago(commit.date))
                            }
                            .font(.custom("Avenir Next", size: 12))
                            .foregroundStyle(DepotColor.subtle)
                        }
                        .padding(.vertical, 6)
                    }
                    Divider().overlay(DepotColor.line)
                }
                if moreCommits {
                    Button("Load more") { Task { await loadCommits(reset: false) } }
                        .font(.custom("Avenir Next", size: 16).weight(.medium))
                }
            }
        case 3:
            if runs.isEmpty {
                Text("No Actions runs.").foregroundStyle(DepotColor.subtle)
            } else {
                ForEach(runs) { run in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(run.name)
                                .font(.custom("Avenir Next", size: 16).weight(.medium))
                            Spacer()
                            Text(run.conclusion.isEmpty ? run.status : run.conclusion)
                                .foregroundStyle(conclusionColor(run.conclusion))
                        }
                        Text(run.title)
                            .foregroundStyle(DepotColor.muted)
                            .lineLimit(2)
                        HStack {
                            Text(run.branch)
                            Spacer()
                            Text(DepotFormat.ago(run.createdAt))
                        }
                        .foregroundStyle(DepotColor.subtle)
                    }
                    .font(.custom("Avenir Next", size: 13))
                    .padding(.vertical, 8)
                    Divider().overlay(DepotColor.line)
                }
            }
        default:
            if readme.isEmpty {
                Text("No README.").foregroundStyle(DepotColor.subtle)
            } else {
                ReadmeBlock(source: readme, owner: shown.owner, repo: shown.name, branch: shown.defaultBranch)
            }
        }
    }

    private func conclusionColor(_ conclusion: String) -> Color {
        switch conclusion {
        case "success": return DepotColor.ok
        case "failure", "cancelled", "timed_out": return DepotColor.danger
        default: return DepotColor.muted
        }
    }

    private func loadMeta() async {
        do {
            live = try await session.api.repo(owner: repo.owner, name: repo.name)
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        guard !session.token.isEmpty else {
            starKnown = true
            return
        }
        do {
            starred = try await session.api.isStarred(owner: repo.owner, name: repo.name)
            starKnown = true
        } catch is CancellationError {
            return
        } catch {
            starKnown = true
        }
    }

    private func loadTab() async {
        error = nil
        loading = true
        do {
            switch tab {
            case 1:
                if releases.isEmpty { releases = try await session.api.releases(owner: repo.owner, name: repo.name) }
            case 2:
                if commits.isEmpty { await loadCommits(reset: true) }
            case 3:
                if runs.isEmpty { runs = try await session.api.actions(owner: repo.owner, name: repo.name) }
            default:
                if readme.isEmpty { readme = try await session.api.readme(owner: repo.owner, name: repo.name) }
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
        loading = false
    }

    private func loadCommits(reset: Bool) async {
        let requested = reset ? 1 : commitPage
        do {
            let batch = try await session.api.commits(owner: repo.owner, name: repo.name, page: requested)
            if reset { commits = batch } else { commits.append(contentsOf: batch) }
            moreCommits = batch.count >= 30
            commitPage = requested + 1
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleStar() async {
        guard !session.token.isEmpty else {
            error = "Add a token in Account to star repositories."
            return
        }
        guard starKnown else { return }
        let next = !starred
        starred = next
        do {
            try await session.api.setStar(owner: shown.owner, name: shown.name, starred: next)
        } catch {
            starred = !next
            self.error = error.localizedDescription
        }
    }

    private func deleteRepo() async {
        do {
            try await session.api.deleteRepo(owner: shown.owner, name: shown.name)
            session.revision += 1
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CommitScreen: View {
    let owner: String
    let name: String
    let sha: String
    let preview: GHCommit
    @EnvironmentObject private var session: Session
    @State private var detail: CommitDetail?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(preview.title)
                    .font(.custom("Avenir Next", size: 22).weight(.medium))
                    .foregroundStyle(DepotColor.fg)
                HStack {
                    Text(preview.authorLogin.isEmpty ? preview.authorName : preview.authorLogin)
                    Text(DepotFormat.shortSHA(sha)).font(.custom("Menlo", size: 12))
                    Spacer()
                    Text(DepotFormat.ago(preview.date))
                }
                .font(.custom("Avenir Next", size: 13))
                .foregroundStyle(DepotColor.subtle)
                if !preview.body.isEmpty {
                    Text(preview.body)
                        .font(.custom("Avenir Next", size: 15))
                        .foregroundStyle(DepotColor.muted)
                }
                if let detail {
                    Text("+\(detail.additions)  −\(detail.deletions)")
                        .font(.custom("Avenir Next", size: 14).weight(.medium))
                        .foregroundStyle(DepotColor.ok)
                    ForEach(detail.files) { file in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(file.filename)
                                    .font(.custom("Menlo", size: 12))
                                    .foregroundStyle(DepotColor.fg)
                                Spacer()
                                Text(file.status)
                                    .font(.custom("Avenir Next", size: 12))
                                    .foregroundStyle(DepotColor.subtle)
                            }
                            if !file.patch.isEmpty {
                                Text(file.patch.count > 6000 ? String(file.patch.prefix(6000)) + "\n…" : file.patch)
                                    .font(.custom("Menlo", size: 11))
                                    .foregroundStyle(DepotColor.muted)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DepotColor.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else if let error {
                    Text(error).foregroundStyle(DepotColor.danger)
                } else {
                    ProgressView()
                }
            }
            .padding(16)
        }
        .background(DepotColor.bg)
        .navigationTitle(DepotFormat.shortSHA(sha))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                detail = try await session.api.commit(owner: owner, name: name, sha: sha)
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct DepotButtonStyle: ButtonStyle {
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Avenir Next", size: 15).weight(.medium))
            .foregroundStyle(filled ? DepotColor.bg : DepotColor.fg)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(filled ? DepotColor.fg : DepotColor.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
