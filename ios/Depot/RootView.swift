import SwiftUI

enum FeedKind {
    case repos
    case search
    case starred
}

struct RootView: View {
    @EnvironmentObject private var session: Session
    @State private var showSettings = false
    @State private var showCreate = false

    var body: some View {
        TabView {
            RepoFeed(kind: .repos, showSettings: $showSettings, showCreate: $showCreate)
                .tabItem { Label("Repos", systemImage: "folder") }
            RepoFeed(kind: .search, showSettings: $showSettings, showCreate: $showCreate)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            RepoFeed(kind: .starred, showSettings: $showSettings, showCreate: $showCreate)
                .tabItem { Label("Starred", systemImage: "star") }
        }
        .background(DepotColor.bg)
        .task {
            await session.loadProfile()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(session)
        }
        .sheet(isPresented: $showCreate) {
            CreateSheet()
                .environmentObject(session)
        }
    }
}

struct RepoFeed: View {
    let kind: FeedKind
    @Binding var showSettings: Bool
    @Binding var showCreate: Bool
    @EnvironmentObject private var session: Session

    @State private var items: [Repo] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var query = ""
    @State private var submitted = "stars:>15000"

    var body: some View {
        NavigationStack {
            List {
                if kind == .search {
                    Section {
                        HStack(spacing: 8) {
                            TextField("owner, language, topic", text: $query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { submitted = query.trimmingCharacters(in: .whitespacesAndNewlines) }
                            Button("Search") {
                                submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            .font(.custom("Avenir Next", size: 16).weight(.medium))
                        }
                        .listRowBackground(DepotColor.elevated)
                    }
                }

                if let banner = banner {
                    Section {
                        Text(banner)
                            .font(.custom("Avenir Next", size: 15))
                            .foregroundStyle(DepotColor.fg)
                            .listRowBackground(DepotColor.elevated)
                    }
                }

                if items.isEmpty && !loading && error == nil {
                    Section {
                        Text(emptyCopy)
                            .font(.custom("Avenir Next", size: 16))
                            .foregroundStyle(DepotColor.muted)
                            .listRowBackground(DepotColor.bg)
                    }
                }

                Section {
                    ForEach(items) { repo in
                        NavigationLink(value: repo) {
                            RepoRow(repo: repo)
                        }
                        .listRowBackground(DepotColor.bg)
                    }
                }

                if hasMore {
                    Section {
                        Button(loading ? "Loading…" : "Load more") {
                            Task { await loadMore() }
                        }
                        .frame(maxWidth: .infinity)
                        .font(.custom("Avenir Next", size: 16).weight(.medium))
                        .disabled(loading)
                        .listRowBackground(DepotColor.bg)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DepotColor.bg)
            .listRowSeparatorTint(DepotColor.line)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Repo.self) { repo in
                RepoDetailView(repo: repo)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if session.token.isEmpty { showSettings = true } else { showCreate = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New repository")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        if let url = session.profile?.avatarURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case let .success(image):
                                    image.resizable().scaledToFill()
                                default:
                                    Image(systemName: "person.crop.circle")
                                }
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .accessibilityLabel("Account")
                }
            }
            .refreshable { await reload() }
            .task(id: taskKey) { await reload() }
        }
    }

    private var title: String {
        switch kind {
        case .repos: return session.token.isEmpty ? "Popular" : "Repos"
        case .search: return "Search"
        case .starred: return "Starred"
        }
    }

    private var taskKey: String {
        switch kind {
        case .repos: return "repos:\(session.revision)"
        case .starred: return "starred:\(session.revision)"
        case .search: return "search:\(session.revision):\(submitted)"
        }
    }

    private var banner: String? {
        if let error { return error }
        if kind == .repos, session.token.isEmpty {
            return "Public repositories, sorted by stars. Add a token in Account for yours."
        }
        if let authError = session.authError, kind == .repos { return authError }
        return nil
    }

    private var emptyCopy: String {
        switch kind {
        case .repos: return "Nothing here yet."
        case .search: return submitted.isEmpty ? "Search GitHub." : "No repositories matched."
        case .starred: return session.token.isEmpty ? "Add a token in Account to see stars." : "No starred repositories."
        }
    }

    private func reload() async {
        page = 1
        hasMore = false
        error = nil
        await fetch(reset: true)
    }

    private func loadMore() async {
        await fetch(reset: false)
    }

    private func fetch(reset: Bool) async {
        if kind == .starred && session.token.isEmpty {
            items = []
            hasMore = false
            return
        }
        if kind == .search && submitted.isEmpty {
            items = []
            hasMore = false
            return
        }
        loading = true
        let requested = reset ? 1 : page
        do {
            let batch: [Repo]
            switch kind {
            case .repos:
                if session.token.isEmpty {
                    batch = try await session.api.search(query: "stars:>15000", page: requested)
                } else {
                    batch = try await session.api.myRepos(page: requested)
                }
            case .search:
                batch = try await session.api.search(query: submitted, page: requested)
            case .starred:
                batch = try await session.api.starred(page: requested)
            }
            if Task.isCancelled { return }
            if reset {
                items = batch
            } else {
                let seen = Set(items.map(\.id))
                items.append(contentsOf: batch.filter { !seen.contains($0.id) })
            }
            hasMore = batch.count >= 30
            page = requested + 1
            error = nil
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            if reset { items = [] }
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct RepoRow: View {
    let repo: Repo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(repo.name)
                    .font(.custom("Avenir Next", size: 17).weight(.medium))
                    .foregroundStyle(DepotColor.fg)
                    .lineLimit(1)
                if repo.isPrivate {
                    Image(systemName: "lock")
                        .font(.caption)
                        .foregroundStyle(DepotColor.subtle)
                }
                Spacer(minLength: 8)
                Label(DepotFormat.compact(repo.stars), systemImage: "star")
                    .font(.custom("Avenir Next", size: 13))
                    .foregroundStyle(DepotColor.muted)
                    .labelStyle(.titleAndIcon)
            }
            Text(repo.owner)
                .font(.custom("Avenir Next", size: 13))
                .foregroundStyle(DepotColor.subtle)
            if !repo.blurb.isEmpty {
                Text(repo.blurb)
                    .font(.custom("Avenir Next", size: 15))
                    .foregroundStyle(DepotColor.muted)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                if !repo.language.isEmpty {
                    HStack(spacing: 5) {
                        Circle().fill(languageColor).frame(width: 8, height: 8)
                        Text(repo.language)
                    }
                }
                if repo.isFork {
                    Label("fork", systemImage: "arrow.triangle.branch")
                }
                Spacer()
                Text(DepotFormat.ago(repo.updatedAt))
            }
            .font(.custom("Avenir Next", size: 12))
            .foregroundStyle(DepotColor.subtle)
        }
        .padding(.vertical, 4)
    }

    private var languageColor: Color {
        switch repo.language {
        case "Swift": return Color(red: 0.94, green: 0.36, blue: 0.22)
        case "TypeScript": return Color(red: 0.18, green: 0.48, blue: 0.85)
        case "JavaScript": return Color(red: 0.94, green: 0.82, blue: 0.25)
        case "Python": return Color(red: 0.22, green: 0.51, blue: 0.72)
        case "Rust": return Color(red: 0.87, green: 0.38, blue: 0.22)
        case "Go": return Color(red: 0.0, green: 0.68, blue: 0.85)
        default: return DepotColor.muted
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("github_pat_…", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Personal access token")
                } footer: {
                    Text("Classic tokens need the repo scope. Deleting a repository also needs delete_repo. Stored in the Keychain on this phone.")
                }
                if let profile = session.profile {
                    Section("Signed in") {
                        LabeledContent("Account", value: profile.login)
                        if !profile.bio.isEmpty {
                            Text(profile.bio)
                                .foregroundStyle(DepotColor.muted)
                        }
                    }
                }
                if let authError = session.authError, !draft.isEmpty {
                    Section {
                        Text(authError)
                            .foregroundStyle(DepotColor.danger)
                    }
                }
                if !session.token.isEmpty {
                    Section {
                        Button("Sign out", role: .destructive) {
                            Task {
                                await session.apply(token: "")
                                draft = ""
                            }
                        }
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(saving)
                }
            }
            .onAppear { draft = session.token }
        }
        .preferredColorScheme(.dark)
    }

    private func save() async {
        saving = true
        await session.apply(token: draft)
        saving = false
        if session.authError == nil {
            dismiss()
        }
    }
}

struct CreateSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var about = ""
    @State private var isPrivate = true
    @State private var readme = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Description", text: $about)
                }
                Section {
                    Toggle("Private", isOn: $isPrivate)
                    Toggle("Add a README", isOn: $readme)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(DepotColor.danger)
                    }
                }
            }
            .navigationTitle("New repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Creating…" : "Create") {
                        Task { await create() }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func create() async {
        saving = true
        error = nil
        do {
            _ = try await session.api.createRepo(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: about.trimmingCharacters(in: .whitespacesAndNewlines),
                isPrivate: isPrivate,
                readme: readme
            )
            session.revision += 1
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}
