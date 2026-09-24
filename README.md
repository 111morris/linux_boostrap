# linux-bootstrap

Cross-distribution Linux workstation provisioning: clone the repository on a
fresh install, run one command, get a machine that is ready for development.

**Status: Stage 1 of a staged build** (see [Roadmap](#roadmap)). Stage 1
delivers the core infrastructure: OS and package-manager detection, a
package-name abstraction across distributions, a configuration system with
explicit precedence, the full command-line interface, dry-run machinery and
logging. System changes begin with Stage 2.

## Supported distributions (Stage 1: detection + package abstraction)

| Family  | Distributions                                      | Package manager |
|---------|----------------------------------------------------|-----------------|
| debian  | Debian, Ubuntu, Mint, Pop, Raspbian, elementary    | apt (apt-get)   |
| rhel    | Fedora, RHEL, CentOS, Rocky, AlmaLinux, Oracle, AMZN | dnf           |
| arch    | Arch, Manjaro, EndeavourOS, Artix, Garuda          | pacman          |
| suse    | openSUSE Leap/Tumbleweed, SLES                     | zypper          |
| alpine  | Alpine                                             | apk             |

Detection reads `/etc/os-release` (including `ID_LIKE` fallback) — no
`lsb_release` dependency. Unsupported distributions fail with a clear error.

## Quick start

```bash
git clone <repository>
cd linux-bootstrap

./bootstrap.sh --list      # what would be detected/used on this machine
./bootstrap.sh --dry-run   # show planned actions, change nothing
./bootstrap.sh             # run (Stage 1 validates only; installs come in Stage 2)
```

## Command line

| Flag                  | Meaning                                                    |
|-----------------------|------------------------------------------------------------|
| `-h, --help`          | Show usage and exit                                        |
| `-V, --version`       | Print version                                              |
| `-n, --dry-run`       | Print every mutating command instead of running it         |
| `--non-interactive`   | Never prompt; use configuration defaults                   |
| `--interactive`       | Request the component menu (arrives in Stage 8)            |
| `--all`               | Enable every registered component                          |
| `--minimal`           | Enable only essential components                           |
| `--skip-update`       | `UPDATE_SYSTEM=false` for this run                         |
| `--modules a,b,c`     | Enable only the named components                           |
| `--list`              | Show environment, components, effective configuration      |

Unknown options/arguments exit with code `2`; runtime failures exit `1`.

## Configuration

Configuration lives in `config/*.conf` and is plain shell syntax (comments
allowed, no dependencies). Precedence, lowest to highest:

```
built-in defaults  <  config/*.conf files  <  environment  <  command line
```

- Unknown keys in config files produce a warning (catches typos).
- Invalid booleans abort the run with a clear error.

Current files: `system.conf` (system behaviour), `software.conf` (component
toggles); `git.conf`, `python.conf`, `node.conf` fill in with later stages.

## Project layout

```
bootstrap.sh        entry point: CLI, orchestration, summary — nothing else
lib/                mechanism: common.sh (log/dry-run/errors), os.sh,
                    pkg.sh (package abstraction), config.sh (precedence)
packages/           data: logical-name maps per OS family (debian, rhel,
                    arch, suse, alpine); unmapped names pass through
modules/            features: one component per file, uniform contract
                    (enabled / check / run / verify) — filled in Stage 2+
config/             user-editable configuration
tests/              zero-dependency test runner + fixtures (no host mutation)
```

Modules request **logical** names (`pkg_install git ripgrep fd`); `lib/pkg.sh`
resolves them per distribution via `packages/<family>.sh`, so package-name
differences never leak into component code.

## Safety

- Runs as your user; `sudo` is used only for system operations.
- `--dry-run` prints every mutating command instead of executing it.
- No secrets, keys or tokens in the repository (SSH handling arrives Stage 4).
- Log file: `~/.local/state/linux-bootstrap/bootstrap.log` (override with
  `BOOTSTRAP_STATE_DIR` / `BOOTSTRAP_LOG_FILE`).
- Colour output auto-disables when piped or when `NO_COLOR` is set.

## Development

```bash
make check    # lint + tests
make lint     # shellcheck (skips with a warning if not installed)
make fmt      # shfmt diff check
make test     # tests/run_tests.sh — plain bash, no test framework needed
```

## Roadmap

| Stage | Content                                          | Status |
|-------|--------------------------------------------------|--------|
| 1     | Core infra: detection, pkg abstraction, config, CLI, dry-run, logging | **current** |
| 2     | System component: metadata refresh, upgrade, baseline packages | pending |
| 3     | Complete `config/*` (git/python/node/system)      | pending |
| 4     | Git + SSH components (non-destructive, opt-in)    | pending |
| 5     | Python + Node runtimes (never replace system)     | pending |
| 6     | Optional runtimes: Rust, Go, Docker               | pending |
| 7     | Applications component (native → flatpak → vendor)| pending |
| 8     | Interactive menu + `--all` / `--minimal`          | pending |
| 9     | Verification, summary, persistent log polish      | pending |
| 10    | Broader test suite + static analysis hardening    | pending |
| 11    | Full documentation + final architecture/security review | pending |

The full specification lives in `prompt.md`; design notes in `note.md`.
