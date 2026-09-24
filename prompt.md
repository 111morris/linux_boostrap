Absolutely. The best approach is to give the coding AI a **master prompt** that tells it to first inspect the repository, understand the architecture, make a plan, and then implement the bootstrap system incrementally rather than blindly rewriting everything.

 You can paste the following prompt into Cursor, Claude Code, Codex, Gemini CLI, or another coding agent.

 # Linux Bootstrap / Workstation Provisioning System

 ## Objective

 I want you to transform this repository into a robust, maintainable Linux workstation bootstrap/provisioning system.

 The purpose of this project is:

 > On a fresh Linux installation, I should be able to clone this repository and run one command that automatically prepares the machine with the software, development tools, configuration, and system settings that I normally use.

 The system must support multiple Linux distributions, especially:

 - Ubuntu
- Debian
- Fedora
- RHEL-compatible distributions where practical
- Arch Linux
- Manjaro where practical
- openSUSE where practical

 The architecture must make it easy to add support for additional distributions later.

 The project should **not** assume that all Linux distributions use the same package manager or package names.

 The system must detect the operating system and use the appropriate installation mechanism automatically.

---

 # IMPORTANT WORKING RULES

 Before modifying anything:

 1. Inspect the entire existing repository.
2. Understand the current project structure.
3. Identify the existing language(s), scripts, configuration files, documentation, tests, CI configuration, and conventions.
4. Do not immediately rewrite existing files.
5. First determine whether the existing architecture can be extended cleanly.
6. Preserve useful existing functionality.
7. Avoid unnecessary dependencies.
8. Prefer simple, portable shell scripting where appropriate.
9. Do not hard-code assumptions about my username, home directory, distribution, package manager, or filesystem layout.
10. Do not silently overwrite existing user configuration files.
11. Make operations idempotent wherever possible.
12. If something is already installed/configured correctly, the script should detect that and skip unnecessary work.
13. Do not install software from untrusted sources.
14. Do not add external repositories unless there is a clear reason and the installation is implemented safely.
15. Never store secrets, passwords, API keys, SSH private keys, or tokens in the repository.
16. Do not make destructive changes to the user's system without explicitly documenting them.
17. Keep the implementation modular.
18. Every major feature should have clear error handling.
19. The script should fail clearly when something goes wrong rather than continuing in a broken state.
20. Documentation must be updated alongside implementation.

---

 # PHASE 1 — ANALYZE THE EXISTING CODEBASE

 Start by inspecting the repository.

 Do not modify anything during this phase.

 Determine:

 - What the project currently does.
- What language(s) it uses.
- What scripts already exist.
- Whether there is already an installation/bootstrap system.
- Whether there are existing configuration files.
- Whether there are tests.
- Whether there is CI/CD.
- Whether there are coding conventions.
- Whether there is documentation.
- Which files should be preserved.
- Which parts should be refactored.
- Which parts should be replaced.

 Create a concise architectural assessment.

 Then propose the target architecture.

 Do not start implementing until the architecture has been reasoned through.

---

 # PHASE 2 — DESIGN THE BOOTSTRAP ARCHITECTURE

 Design the system around separate responsibilities.

 A preferred structure is approximately:

```
project/
├── bootstrap.sh
├── config/
│   ├── software.conf
│   ├── git.conf
│   └── system.conf
│
├── modules/
│   ├── common.sh
│   ├── detect_os.sh
│   ├── package_manager.sh
│   ├── system.sh
│   ├── git.sh
│   ├── ssh.sh
│   ├── shell.sh
│   ├── python.sh
│   ├── node.sh
│   ├── docker.sh
│   ├── rust.sh
│   ├── go.sh
│   └── applications.sh
│
├── packages/
│   ├── common.sh
│   ├── debian.sh
│   ├── fedora.sh
│   ├── arch.sh
│   └── opensuse.sh
│
├── tests/
│   └── ...
│
└── README.md
```

 This is only a suggested structure.

 Adapt it to the existing repository if a better structure is appropriate.

 The important architectural principle is:

```
bootstrap.sh
      |
      +-- detect operating system
      |
      +-- detect package manager
      |
      +-- update system
      |
      +-- install common dependencies
      |
      +-- configure Git
      |
      +-- configure SSH
      |
      +-- install developer runtimes
      |
      +-- install applications
      |
      +-- configure shell
      |
      +-- verify installation
```

---

 # PHASE 3 — OPERATING SYSTEM DETECTION

 Implement reliable Linux distribution detection.

 Use `/etc/os-release` as the primary source.

 The system should determine at least:

 - distribution ID
- distribution name
- version
- version ID
- architecture

 Examples:

```
ubuntu
debian
fedora
rhel
rocky
almalinux
arch
manjaro
opensuse
```

 Do not rely only on commands such as:

```
lsb_release
```

 because they may not be installed.

 Create a clean abstraction so the rest of the application can ask:

```
What operating system am I running?
What package manager should I use?
```

 without needing to know the details of `/etc/os-release`.

 Unsupported distributions should produce a clear error message.

---

 # PHASE 4 — PACKAGE MANAGER ABSTRACTION

 Implement package-manager abstraction.

 Support where practical:

 ### Debian/Ubuntu

```
apt
apt-get
```

 ### Fedora/RHEL

```
dnf
```

 ### Arch

```
pacman
```

 ### openSUSE

```
zypper
```

 ### Alpine

 Support Alpine only if doing so does not unnecessarily complicate the architecture.

 The rest of the code should not repeatedly contain large blocks such as:

```
if ubuntu; then
    apt install ...
elif fedora; then
    dnf install ...
fi
```

 Instead create reusable functions such as:

```
package_update
package_install
package_is_installed
package_remove
```

 or an equivalent clean abstraction.

 For example:

```
package_install git curl wget
```

 should work regardless of whether the underlying package manager is:

```
apt
dnf
pacman
zypper
```

---

 # PHASE 5 — SYSTEM UPDATE

 Implement a system update stage.

 The bootstrap process should be able to:

 1. Detect the distribution.
2. Refresh package metadata.
3. Update installed packages where appropriate.
4. Handle errors clearly.

 Do not blindly assume every distribution should be upgraded in exactly the same way.

 Separate:

```
package metadata refresh
```

 from:

```
system upgrade
```

 if appropriate.

 Make system upgrades configurable.

 For example:

```
UPDATE_SYSTEM=true
```

 The user should be able to disable the full upgrade if desired.

---

 # PHASE 6 — COMMON DEVELOPMENT PACKAGES

 Create a common baseline of tools that I normally want on almost every development machine.

 At minimum consider:

 - git
- curl
- wget
- ca-certificates
- unzip
- zip
- tar
- gzip
- openssh client
- build tools
- make
- compiler/toolchain
- jq
- tree
- tmux
- htop
- ripgrep
- find utilities
- vim or another basic editor

 Do not assume that package names are identical across distributions.

 For example:

```
Debian/Ubuntu package name
Fedora package name
Arch package name
openSUSE package name
```

 should be represented separately where necessary.

 Avoid installing unnecessary software merely because it is available.

---

 # PHASE 7 — GIT

 Implement Git setup as a separate module.

 The system should:

 1. Check whether Git exists.
2. Install it if missing.
3. Check the current Git configuration.
4. Configure values specified by the user.
5. Avoid overwriting unrelated Git configuration.

 Configuration should be externalized.

 For example:

```
GIT_USER_NAME=""
GIT_USER_EMAIL=""
GIT_DEFAULT_BRANCH="main"
GIT_EDITOR=""
```

 The bootstrap system should not contain my actual personal identity unless I explicitly configure it.

 Support settings such as:

```
user.name
user.email
init.defaultBranch
core.editor
pull.rebase
color.ui
```

 Only configure settings that have been explicitly enabled.

---

 # PHASE 8 — SSH

 Create an SSH configuration module.

 It should:

 - Check whether an SSH client exists.
- Install it if required.
- Check whether an SSH key already exists.
- Never overwrite an existing private key.
- Allow the user to optionally generate a new key.
- Configure sensible permissions.
- Explain what happened.

 Do not automatically upload keys anywhere.

 Do not automatically modify GitHub/GitLab/etc. accounts.

 Do not expose private key contents.

 If SSH key generation is implemented, make it explicitly opt-in.

---

 # PHASE 9 — PYTHON

 Implement Python installation as a developer-runtime module.

 Requirements:

 - Ensure Python 3 exists.
- Ensure pip is available where appropriate.
- Ensure virtual environments can be created.
- Verify the installed version.
- Do not replace the distribution's system Python unnecessarily.
- Do not break OS tooling that depends on the system Python.

 This is extremely important.

 Never blindly replace:

```
/usr/bin/python3
```

 with a manually installed version.

 Prefer a user-space version manager when a specific Python version is required.

 The architecture should allow future support for tools such as:

```
pyenv
mise
```

 without coupling the entire project to them.

---

 # PHASE 10 — NODE.JS

 Implement Node.js support.

 Requirements:

 - Detect whether Node.js is already installed.
- Detect the installed version.
- Ensure npm is available.
- Avoid blindly replacing an existing Node installation.
- Allow a configurable Node.js version.
- Prefer a version-management strategy for development environments when appropriate.

 The architecture should allow future support for:

```
nvm
mise
fnm
```

 without hard-coding one solution throughout the application.

---

 # PHASE 11 — OTHER DEVELOPMENT RUNTIMES

 Create optional modules for:

 - Rust
- Go
- Java
- PHP
- Ruby

 Do not install all of these by default.

 Instead expose configuration such as:

```
INSTALL_RUST=false
INSTALL_GO=false
INSTALL_JAVA=false
INSTALL_PHP=false
INSTALL_RUBY=false
```

 When enabled:

 1. Detect whether it already exists.
2. Install it using an appropriate method.
3. Verify installation.
4. Avoid breaking an existing installation.

---

 # PHASE 12 — APPLICATION INSTALLATION

 Create a clean mechanism for defining applications I want installed.

 Examples could include:

```
Docker
Docker Compose
Neovim
Visual Studio Code
Firefox
Chromium
PostgreSQL
Redis
```

 Do not assume all applications are available through the same package manager.

 Support multiple installation methods where necessary:

```
native package manager
Flatpak
official vendor repository
official installer
```

 However, prefer the distribution package manager when it is sufficiently suitable.

 Do not add third-party repositories unnecessarily.

 Make each application independently configurable.

 For example:

```
INSTALL_DOCKER=true
INSTALL_NEOVIM=true
INSTALL_VSCODE=false
INSTALL_POSTGRESQL=false
INSTALL_REDIS=false
```

---

 # PHASE 13 — CONFIGURATION SYSTEM

 Create a central configuration system.

 I want to be able to define something like:

```
UPDATE_SYSTEM=true

INSTALL_GIT=true
INSTALL_PYTHON=true
INSTALL_NODE=true

INSTALL_RUST=false
INSTALL_GO=false
INSTALL_JAVA=false

INSTALL_DOCKER=true
INSTALL_NEOVIM=true
INSTALL_VSCODE=false

INSTALL_POSTGRESQL=false
INSTALL_REDIS=false
```

 The exact format can be adapted to the existing project.

 Prefer a configuration format that:

 - is easy to edit
- does not require a large dependency
- works on a fresh Linux installation
- can be version controlled
- supports comments
- has sensible defaults

 Shell configuration is acceptable if it produces the cleanest and most portable result.

---

 # PHASE 14 — INTERACTIVE MODE

 Implement an optional interactive mode.

 Running:

```
./bootstrap.sh
```

 should ideally allow the user to choose optional components.

 Example:

```
Linux Bootstrap

Detected OS: Fedora

Select components:

[x] System update
[x] Git
[x] Python
[x] Node.js
[x] SSH
[x] Docker
[x] Neovim
[ ] Rust
[ ] Go
[ ] PostgreSQL
[ ] Redis

Continue? [Y/n]
```

 Do not make interactive prompts mandatory for automation.

---

 # PHASE 15 — NON-INTERACTIVE MODE

 The system must also support automation.

 For example:

```
./bootstrap.sh --non-interactive
```

 should use configuration defaults without asking questions.

 Support useful flags such as:

```
--help
--version
--dry-run
--non-interactive
--minimal
--all
--skip-update
```

 Only implement options that make architectural sense.

---

 # PHASE 16 — DRY RUN

 Implement:

```
./bootstrap.sh --dry-run
```

 The script should show what it intends to do without actually modifying the system.

 Example:

```
DRY RUN

Would update package repositories
Would install git
Would install curl
Would install Python 3
Would install Node.js
Would configure Git
Would install Docker
```

 No installation or configuration should happen in dry-run mode.

---

 # PHASE 17 — IDEMPOTENCY

 This is a critical requirement.

 The bootstrap process must be safe to execute multiple times.

 Example:

 First execution:

```
Installing Git...
Installing Python...
Installing Node.js...
Configuring Git...
```

 Second execution:

```
Git already installed
Python already installed
Node.js already installed
Git configuration already correct
Nothing to change
```

 Avoid unnecessary modifications.

 Do not append the same shell configuration to `.bashrc` every time.

 Before modifying files, detect whether the configuration already exists.

---

 # PHASE 18 — USER CONFIGURATION SAFETY

 The script must respect existing user configuration.

 Never blindly overwrite:

```
~/.bashrc
~/.zshrc
~/.profile
~/.gitconfig
~/.ssh/config
~/.ssh/*
```

 Create backups before modifying user configuration when appropriate.

 Prefer managed configuration blocks such as:

```
# BEGIN linux-bootstrap
...
# END linux-bootstrap
```

 This allows the bootstrap system to update only the configuration it owns.

---

 # PHASE 19 — SHELL CONFIGURATION

 Support common shells where practical:

```
bash
zsh
fish
```

 Do not assume Bash is always the user's shell.

 Detect the current shell.

 Only install/configure optional shell components when enabled.

 Potential configuration areas:

 - PATH
- aliases
- environment variables
- shell prompt
- developer tooling

 Keep this modular.

---

 # PHASE 20 — LOGGING

 Implement useful logging.

 The script should clearly communicate:

```
[INFO]
[OK]
[WARN]
[ERROR]
[SKIP]
```

 Example:

```
[INFO] Detecting operating system...
[OK] Fedora 43 detected.

[INFO] Checking Git...
[OK] Git already installed.

[INFO] Checking Docker...
[INFO] Docker not installed.
[INFO] Installing Docker...
[OK] Docker installed.
```

 Errors should explain:

 - what failed
- which operation failed
- what the user can do about it

 Avoid swallowing errors.

---

 # PHASE 21 — ERROR HANDLING

 Use strict shell scripting practices where appropriate.

 For Bash, consider:

```
set -Eeuo pipefail
```

 but use it intelligently.

 Do not introduce brittle shell behavior merely for the sake of using strict mode.

 Implement:

 - meaningful error messages
- cleanup where necessary
- exit codes
- traps where useful
- validation of required commands
- checks for network availability where appropriate

---

 # PHASE 22 — PRIVILEGE MANAGEMENT

 The script should use elevated privileges only when necessary.

 Do not run the entire script as root unless there is a compelling reason.

 Prefer:

```
sudo command
```

 for individual system operations.

 User configuration should normally happen as the actual user.

 Avoid creating root-owned files inside:

```
$HOME
```

---

 # PHASE 23 — VERIFICATION

 After installation, verify the important components.

 For example:

```
Git       ✓
Python    ✓
pip       ✓
Node      ✓
npm       ✓
SSH       ✓
Docker    ✓
Rust      ✓
Go        ✓
```

 Only show components that were enabled.

 If something failed, the final summary should make that obvious.

 Example:

```
Bootstrap completed with warnings.

Successful:
  ✓ Git
  ✓ Python
  ✓ Node.js
  ✓ SSH

Failed:
  ✗ Docker

See log:
  ~/.local/state/linux-bootstrap/bootstrap.log
```

---

 # PHASE 24 — LOG FILE

 Implement persistent logging if practical.

 Prefer a user-owned location such as:

```
~/.local/state/linux-bootstrap/
```

 Do not write logs containing secrets.

 Make the log location configurable.

---

 # PHASE 25 — TESTING

 Add tests appropriate for the project.

 At minimum, test:

 1. OS detection.
2. Package-manager detection.
3. Unsupported distribution handling.
4. Package installation abstraction.
5. Configuration parsing.
6. Idempotency where practical.
7. Dry-run behavior.
8. Command-line argument parsing.

 Do not require the tests to modify the real host system.

 Use mocking/stubs where necessary.

 If shell-based tests are appropriate, consider:

```
bats
shellcheck
shfmt
```

 only if introducing these tools is justified.

---

 # PHASE 26 — STATIC ANALYSIS

 If Bash is used, ensure the scripts are compatible with:

```
shellcheck
```

 and format them consistently.

 Fix meaningful ShellCheck warnings rather than blindly suppressing them.

 Use a consistent shell style throughout the project.

---

 # PHASE 27 — DOCUMENTATION

 Create/update `README.md`.

 It should explain:

 ## What this project does

 Explain that it provisions a fresh Linux workstation.

 ## Supported distributions

 List the currently supported distributions.

 ## Quick start

 Show something like:

```
git clone <repository>
cd <repository>
chmod +x bootstrap.sh
./bootstrap.sh
```

 ## Configuration

 Explain how to enable/disable software.

 ## Interactive mode

 Explain how it works.

 ## Non-interactive mode

 Explain how automation works.

 ## Dry-run

 Explain:

```
./bootstrap.sh --dry-run
```

 ## Adding new software

 Explain exactly where a user should add another application.

 ## Adding a new Linux distribution

 Explain exactly which files/functions need to be changed.

 ## Safety

 Explain:

 - sudo usage
- configuration backups
- idempotency
- third-party repositories
- SSH handling
- secrets

---

 # PHASE 28 — EXTENSIBILITY

 The project should be designed so adding software later is easy.

 I want to eventually be able to say:

```
Install Docker
Install PostgreSQL
Install Redis
Install Kubernetes tools
Install Terraform
Install AWS CLI
Install Azure CLI
Install Google Cloud CLI
Install Ansible
Install Neovim
Install VS Code
```

 without rewriting the entire bootstrap script.

 Ideally adding a component should involve creating or modifying one small module plus configuration.

---

 # PHASE 29 — SECURITY REQUIREMENTS

 Treat this as a system administration tool.

 Never:

 - download and execute arbitrary remote scripts without verification
- pipe unknown URLs directly into `bash`
- store secrets in the repository
- expose SSH private keys
- overwrite private keys
- disable security mechanisms
- modify firewall configuration unnecessarily
- add insecure repositories
- use `curl | bash` unless absolutely unavoidable and the source is trusted and documented

 When third-party installation is required, prefer:

 1. distribution package
2. official repository
3. verified official release
4. official installer as a last resort

 Document why a particular method is used.

---

 # PHASE 30 — FINAL USER EXPERIENCE

 The final system should make this possible:

```
git clone <repository>
cd <repository>

./bootstrap.sh
```

 Then I should get a usable development machine.

 The final output should look something like:

```
====================================================
 Linux Bootstrap
====================================================

System
  Distribution : Fedora 43
  Architecture : x86_64
  Package mgr  : dnf

Core
  ✓ System packages
  ✓ Git
  ✓ SSH
  ✓ Build tools

Development
  ✓ Python
  ✓ Node.js
  ✓ npm
  ✓ Rust

Applications
  ✓ Docker
  ✓ Neovim
  - VS Code (disabled)
  - PostgreSQL (disabled)

Configuration
  ✓ Git configuration
  ✓ Shell configuration

====================================================
Bootstrap completed successfully.
====================================================
```

---

 # IMPLEMENTATION PROCESS

 Do not implement everything in one giant change.

 Work in stages.

 ## Stage 1

 Analyze the existing repository and propose the architecture.

 ## Stage 2

 Implement OS and package-manager detection.

 ## Stage 3

 Implement system update and common package installation.

 ## Stage 4

 Implement configuration management.

 ## Stage 5

 Implement Git and SSH.

 ## Stage 6

 Implement Python and Node.js.

 ## Stage 7

 Implement optional runtimes.

 ## Stage 8

 Implement optional applications.

 ## Stage 9

 Implement interactive/non-interactive modes.

 ## Stage 10

 Implement dry-run support.

 ## Stage 11

 Implement verification and logging.

 ## Stage 12

 Add tests and static analysis.

 ## Stage 13

 Update documentation.

 ## Stage 14

 Perform a final architecture and security review.

 After each stage:

 1. Run the relevant tests.
2. Run ShellCheck where applicable.
3. Verify that existing functionality has not been broken.
4. Review the changes.
5. Fix issues before moving to the next stage.

---

 # IMPORTANT: DO NOT GUESS

 If the existing codebase already has an architecture that differs from the suggested structure, do not force the suggested structure onto it.

 Adapt the design to the existing project.

 If there are multiple reasonable approaches, explain the trade-offs and choose the simplest maintainable solution.

 If an operation could be destructive, stop and explicitly identify the risk before implementing it.

 If a requirement is ambiguous, inspect the existing project first and make the smallest reasonable assumption.

 Do not invent existing files, modules, APIs, or configuration.

---

 # FINAL REQUIREMENT

 At the end of the implementation, provide:

 1. A summary of the architecture.
2. A list of files created.
3. A list of files modified.
4. A list of files removed, if any.
5. Supported Linux distributions.
6. Supported package managers.
7. Supported software/components.
8. Available CLI commands/options.
9. How to perform a dry run.
10. How to add new software.
11. How to add another Linux distribution.
12. How to run the tests.
13. Any known limitations.
14. Any security considerations.
15. Any remaining TODOs.

 Most importantly:

 **Do not just make a script that happens to work on one Linux distribution. Build a maintainable cross-distribution provisioning system that I can continue extending for years.**

