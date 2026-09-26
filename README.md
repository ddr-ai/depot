# Depot

GitHub on iPhone. Repos, search, stars, README, releases, commits, and Actions. Your token stays in the Keychain.

The GitHub Action builds an **unsigned** IPA and publishes it on the `ios-latest` release. Download that file and sideload it with SideStore, AltStore, Sideloadly, or Feather. Those apps sign it with your Apple ID.

Direct download (replaced on every build):

https://github.com/ddr-ai/depot/releases/download/ios-latest/Depot.ipa

In the app, open Account and paste a GitHub personal access token. Classic tokens need the `repo` scope. Deleting a repository needs `delete_repo`.
