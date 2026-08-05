---
name: update-easy-dotnet
description: Update the EasyDotnet server checkout and the sibling easy-dotnet-server-flake package pin, NuGet dependency lock, and verification state. Use when asked to update, bump, or refresh EasyDotnet together with its Nix flake, including requests such as "update the flake and server".
---

# Update EasyDotnet

Update the upstream server first, then make the flake reproducibly package that exact revision. Keep both repositories clean except for the intended flake changes.

## Locate and preflight both repositories

Treat the repository containing this skill as the flake repository. Locate the server checkout at the sibling path `../easy-dotnet-server` unless the user provides another path.

In both repositories:

1. Run `git status --short --branch`.
2. Confirm the branch and remotes.
3. Preserve unrelated changes. Stop and ask before touching files that overlap this update.

Do not commit or push unless the user explicitly requests it.

## Update the server checkout

1. Run `git pull --ff-only` in the server repository.
2. Record the full revision with `git rev-parse HEAD`.
3. Read the package version from `EasyDotnet.IDE/EasyDotnet.IDE.csproj`.
4. Review the incoming commits and note changes that could affect `easy-dotnet.patch`, payload paths, project names, target frameworks, SDK requirements, or smoke-test commands.

The server checkout should remain clean after the fast-forward.

## Refresh the flake pin

1. Fast-forward the flake repository with `git pull --ff-only` when its worktree is clean.
2. Calculate the unpacked source hash for the full server revision:

   ```bash
   nix-prefetch-url --unpack https://github.com/GustavEikaas/easy-dotnet-server/archive/<full-revision>.tar.gz
   nix hash convert --hash-algo sha256 --to sri <nix-base32-hash>
   ```

3. In `easy-dotnet.nix`, update:
   - `version` to the value from `EasyDotnet.IDE.csproj`
   - `src.rev` to the full server revision
   - `src.hash` to the SRI hash
4. Preserve the existing Nix-specific patch and packaging behavior unless the new source proves they must change.

Use `apply_patch` for edits.

## Refresh NuGet dependencies

Use the `buildDotnetModule` updater rather than manually editing `deps.json`:

```bash
update_dir=$(mktemp -d)
nix build .#easy-dotnet.fetch-deps --out-link "$update_dir/fetch-deps"
"$update_dir/fetch-deps" ./deps.json
```

It is valid for `deps.json` to remain unchanged when the updated server uses the same resolved dependency graph. Never force a meaningless lockfile diff.

The updater also applies `easy-dotnet.patch`; treat a patch failure as a prompt to inspect upstream changes and revise only the obsolete patch hunks.

## Build and smoke-test

Build to a temporary output link:

```bash
build_dir=$(mktemp -d)
nix build .#easy-dotnet --out-link "$build_dir/easy-dotnet"
```

Run both smoke tests against that output:

```bash
"$build_dir/easy-dotnet/bin/dotnet-easydotnet" roslyn start --version
timeout 20 "$build_dir/easy-dotnet/bin/dotnet-easydotnet" roslyn start --roslynator --easy-dotnet-analyzer --easy-dotnet-extension
```

Require the analyzer-enabled command to emit `Language server initialized`. A read-only Roslyn cache warning can be sandbox-specific; do not confuse it with failure to initialize. Investigate missing payloads, patch errors, assembly load failures, or a missing initialization message.

Then run:

```bash
nix flake check
git diff --check
git status --short --branch
git diff --stat
```

Confirm that the final flake diff contains only the intended pin/version/hash, dependency-lock changes when real, and any necessary compatibility updates. Remove only temporary output links created by this workflow.

## Report the result

Report:

- old and new server revisions
- old and new package versions
- whether `deps.json` changed
- build, flake-check, and both smoke-test results
- files changed in the flake repository
- any sandbox-only warning separately from product failures

Leave commit, push, and downstream consumer lock updates for explicit follow-up requests.
