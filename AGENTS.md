# AGENTS.md

## Project

- This repository is a macOS-only shell CLI for discovering unmanaged `.app` bundles and switching them to Homebrew management. Keep detailed user-facing behavior and examples in [README.md](README.md) rather than duplicating them here.
- Main flow: `switch-to-brew` -> `stb_do_discover` -> `stb_discover_apps` -> `stb_cask_resolve_all` -> `stb_brew_adopt_batch`.

## Editing Rules

- Keep compatibility with macOS `/bin/bash` 3.2. Do not introduce Bash 4+ features such as associative arrays, `mapfile`/`readarray`, or case-conversion parameter expansions.
- Preserve the existing shell style in `lib/`: small functions, `local` variables, temp files for cross-subshell state, and `grep`/`awk`/`sed` pipelines instead of refactoring into a different scripting model.
- Preserve TSV contracts exactly.
- `data/known_casks.tsv` is `bundle_id<TAB>brew_token<TAB>app_name<TAB>package_type(optional)`.
- Discovery and switch pipelines use `app_name<TAB>cask_token<TAB>app_path<TAB>source<TAB>bundle_id<TAB>package_type`.
- Treat `package_type` as real behavior, not display-only metadata. Formula-backed mappings must stay `formula` all the way through discovery, `list`, direct `switch`, and batch adopt.

## Key Files

- [switch-to-brew](switch-to-brew): argument parsing, command dispatch, direct package switch input generation.
- [lib/discovery.sh](lib/discovery.sh): scans `/Applications` and `~/Applications`, filters Apple apps, App Store apps, Setapp apps, and already-managed packages.
- [lib/cask_match.sh](lib/cask_match.sh): known mapping lookup, fallback Homebrew search, package-type detection.
- [lib/brew_ops.sh](lib/brew_ops.sh): cask adoption, formula installs, version-mismatch handling, optional upgrades.
- [data/known_casks.tsv](data/known_casks.tsv): curated mappings; start here when adding or fixing app support.

## Validation

- For contributor-facing validation commands, see [README.md](README.md).
- After edits, prefer the narrowest relevant check from that list for the behavior you changed.

## Pitfalls

- Formula-backed apps do not use `brew install --cask --adopt`; they install via `brew install <formula>` and may leave the existing `.app` bundle in place.
- Some casks prompt for `sudo` because Homebrew invokes `.pkg` installers or privileged helpers. That is expected platform behavior.
- Cache state lives under `${TMPDIR:-/tmp}/switch-to-brew-$USER`. Clear it with `switch-to-brew cache clear` when validating discovery or matching changes.
