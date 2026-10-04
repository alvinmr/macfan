# Releasing

Releases are automated with [release-please](https://github.com/googleapis/release-please).

## Day to day

Write commits in [Conventional Commits](https://www.conventionalcommits.org) style:

| Commit | Effect on the next version |
| --- | --- |
| `fix: restore fans after wake` | patch (0.1.0 → 0.1.1) |
| `feat: add M5 GPU sensors` | minor (0.1.0 → 0.2.0) |
| `feat!: …` or `BREAKING CHANGE:` in the body | major |
| `docs:`, `chore:`, `test:`, `refactor:` | no release |

On every push to `main`, release-please keeps a **release PR** up to date with the next
version and changelog. **Merging that PR is the release.** The workflow then:

1. tags `vX.Y.Z` and creates the GitHub release,
2. runs the tests,
3. builds a universal `MacFan.app` and `MacFan-vX.Y.Z-macOS.dmg` plus its `.sha256`,
4. uploads them (and a version-less `MacFan-macOS.dmg` for the README's download link),
5. publishes the Sparkle `appcast.xml`, so installed copies update themselves,
6. bumps the Homebrew cask in `alvinmr/homebrew-tap`.

To rebuild an existing release: **Actions → Release → Run workflow**, with `release_tag`.

## Repository secrets

| Secret | Needed for | Without it |
| --- | --- | --- |
| `SPARKLE_PRIVATE_KEY` | Automatic updates | No appcast; users update manually |
| `TAP_GITHUB_TOKEN` | Homebrew cask bump (a token with write access to `alvinmr/homebrew-tap`) | Cask must be bumped by hand |
| `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PASSWORD` | Developer ID signing (base64 `.p12`) | Ad-hoc signed; Gatekeeper prompt |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Notarization | Not notarized |

The Sparkle private key lives in the maintainer's login Keychain (account `macfan`).
Export it with Sparkle's `generate_keys --account macfan -x key.txt`. **Never commit it.**
The matching public key is `SUPublicEDKey` in `Resources/Info.plist`; if the private key
is ever lost, existing installs can no longer verify updates.

## Going from ad-hoc to Developer ID

With an Apple Developer Program membership, add the four signing and notarization
secrets above. The next release is signed, notarized and stapled automatically, and the
privileged helper starts pinning clients to your team ID. No code changes are needed.
