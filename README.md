# switch-to-brew

**Discover macOS apps that aren't managed by [Homebrew](https://brew.sh) — and switch them over in one command.**

Many of us install apps from `.dmg` files, direct downloads, or vendor websites. Over time this creates a patchwork of apps that don't benefit from Homebrew's unified update management (`brew upgrade --cask`). **switch-to-brew** finds those apps, shows you which ones have Homebrew cask equivalents, and lets you selectively adopt them — without reinstalling.

---

## ✨ Features

- 🔍 **Smart discovery** — scans `/Applications` and `~/Applications`, filters out Apple system apps, Homebrew-managed apps, and installers/helpers
- ⚡ **Fast matching** — ships with a curated mapping of 90+ popular apps to their cask tokens; falls back to `brew search` for the rest (with caching)
- 🎯 **Interactive selection** — pick exactly which apps to switch using numbers, ranges, or "all"
- 🔒 **Non-destructive** — uses `brew install --cask --adopt` to link your existing `.app` bundle into Homebrew tracking, no reinstall needed
- 🏃 **Dry-run mode** — see exactly what would happen before committing
- 📋 **Machine-readable output** — TSV and JSON formats for scripting
- 🎨 **Beautiful terminal UI** — colors, spinners, and clean formatting (respects `NO_COLOR`)

## 📦 Installation

### Quick start (run from source)

```bash
git clone https://github.com/matthewcorven/switch-to-brew.git
cd switch-to-brew
chmod +x switch-to-brew
./switch-to-brew
```

### Install system-wide

```bash
git clone https://github.com/matthewcorven/switch-to-brew.git
cd switch-to-brew
sudo make install
```

This installs to `/usr/local/bin`. Customise with `PREFIX`:

```bash
make install PREFIX="$HOME/.local"
```

### Uninstall

```bash
sudo make uninstall
```

## 🚀 Usage

### Interactive mode (default)

Just run it — it discovers apps, shows matches, and lets you pick:

```
$ switch-to-brew

▸ Scanning for applications...
▸ Found 35 unmanaged apps. Resolving casks...
▸ Matched 28 of 35 apps to Homebrew casks.

  #   Application                        Cask                                 Source
  ──────────────────────────────────────────────────────────────────────────────────────
  1   ChatGPT                            chatgpt                              manual
  2   Docker                             docker                               manual
  3   Google Chrome                      google-chrome                        manual
  4   iTerm                              iterm2                               manual
  5   Microsoft Word                     microsoft-word                       manual
  6   Obsidian                           obsidian                             manual
  7   Signal                             signal                               manual
  8   Visual Studio Code                 visual-studio-code                   manual
  ...

Select apps to switch to Homebrew:
  Enter numbers separated by spaces (e.g. 1 3 5)
  Ranges work too (e.g. 1-5 8 10-12)
  Type "all" to select everything, "q" to cancel

❯ 1-4 6

▸ Selected 5 apps to switch:
  ...

Proceed with switching? [y/N] y

▸ Adopting ChatGPT via cask chatgpt...
✔ ChatGPT is now managed by Homebrew (chatgpt)
▸ Adopting Docker via cask docker...
✔ Docker is now managed by Homebrew (docker)
...

── Summary ─────────────────────────────────────
✔ 5 apps switched to Homebrew
```

### Discover only (no changes)

```bash
switch-to-brew discover          # Pretty table
switch-to-brew discover --json   # JSON output
switch-to-brew list              # TSV for scripting
```

### Switch specific apps

```bash
switch-to-brew switch docker obsidian signal
```

### Switch everything

```bash
switch-to-brew switch --all
```

### Handle version mismatches

If the installed version of an app differs from what the Homebrew cask currently ships, `--adopt` alone will fail. By default, **switch-to-brew** automatically retries with `--force` and shows a warning:

```
⚠ Version mismatch: GIMP installed=3.0.6, cask=3.2.0
▸ Retrying with --force (brew upgrade will update it later)...
✔ GIMP force-adopted (3.0.6 → brew upgrade will bring to 3.2.0)
```

To immediately upgrade to the latest version after adopting:

```bash
switch-to-brew switch gimp --upgrade          # Adopt + upgrade one app
switch-to-brew switch --all --upgrade         # Adopt + upgrade everything
switch-to-brew --upgrade                      # Interactive mode with upgrade
```

To disable force-retry and fail on any version mismatch:

```bash
switch-to-brew switch gimp --strict
```

### Dry run

Preview what would happen without making any changes:

```bash
switch-to-brew --dry-run                # Interactive dry run
switch-to-brew --dry-run switch --all   # Batch dry run
```

### Include Mac App Store apps

By default, App Store apps are excluded (they must be removed from the App Store before Homebrew can manage them). Include them in discovery with:

```bash
switch-to-brew --app-store discover
```

## 🔧 How it works

1. **Scan** — walks `/Applications` and `~/Applications` for `.app` bundles
2. **Filter** — removes Apple system apps (by `com.apple.*` bundle ID), apps already managed by `brew list --cask`, helper/installer bundles, and Mac App Store apps
3. **Match** — resolves each app to a Homebrew cask token:
   - First checks a built-in mapping of 90+ common apps (`data/known_casks.tsv`)
   - Falls back to `brew search --cask` with normalised name variants
   - Results are cached for 5 minutes to speed up repeated runs
4. **Adopt** — runs `brew install --cask <token> --adopt` which tells Homebrew to claim the existing `.app` bundle rather than downloading a fresh copy

### What does `--adopt` do?

When you run `brew install --cask foo --adopt`, Homebrew:
- Downloads the cask metadata (version tracking, uninstall instructions, etc.)
- Sees that the `.app` already exists in `/Applications`
- **Links** the existing app into its tracking system instead of replacing it
- From this point on, `brew upgrade` will manage updates for this app

Your app, its settings, and its data are untouched.

## 📁 Project structure

```
switch-to-brew/
├── switch-to-brew           # Main executable
├── lib/
│   ├── constants.sh         # Colors, version, exit codes
│   ├── utils.sh             # Logging, cache, confirm, helpers
│   ├── discovery.sh         # App scanning and filtering
│   ├── cask_match.sh        # Cask name resolution
│   ├── ui.sh                # Table rendering, interactive picker
│   └── brew_ops.sh          # brew install --adopt operations
├── data/
│   └── known_casks.tsv      # Curated app → cask mapping
├── Makefile                  # install / uninstall / lint
├── LICENSE                   # MIT
└── README.md
```

## 🤝 Contributing

Contributions are welcome! Common ways to help:

- **Add entries to `data/known_casks.tsv`** — if you notice an app that isn't matched, add its bundle ID → cask mapping
- **Report mismatches** — if an app is matched to the wrong cask, open an issue
- **Test on different macOS versions** — the more environments tested, the better

### Running the linter

```bash
make lint    # requires shellcheck
```

## ⚠️ Caveats

- **App Store apps** require manual removal from the App Store before Homebrew can manage them. By default they're excluded from discovery.
- **Setapp apps** are discovered and flagged but may not work correctly with `--adopt` since Setapp manages its own app lifecycle.
- **Version mismatches** — if your installed version differs from the Homebrew cask version, `--adopt` alone will fail. By default, **switch-to-brew** detects this and retries with `--force` so Homebrew takes ownership of your existing binary. Run `brew upgrade --cask` later (or pass `--upgrade`) to update to the latest version. Use `--strict` to fail on mismatch instead.
- Requires **Homebrew** to be installed. Requires **macOS** (this tool uses macOS-specific APIs like `defaults read` and `mdls`).

## 📄 License

[MIT](LICENSE) © Matthew Corven
