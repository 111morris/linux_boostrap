System packages
    ↓
apt / dnf / pacman / zypper

Developer runtimes
    ↓
mise / rustup / official installers / etc.

Applications
    ↓
native package manager
Flatpak
Snap
AppImage
official installer




                    bootstrap.sh
                         │
          ┌──────────────┼──────────────┐
          ↓              ↓              ↓
       System         Developer       Apps
       packages       runtimes
          │              │              │
     apt/dnf/etc.      Python          Docker
                       Node            VS Code
                       Go              Firefox
                       Rust            etc.

I'd also make the script interactive

Linux Bootstrap
===============

Detected OS: Fedora 43

What would you like to install?

[x] Git
[x] Python
[x] Node.js
[x] Build tools
[x] SSH
[x] Docker
[x] Neovim
[ ] Go
[ ] Rust
[ ] PostgreSQL
[ ] Redis

Continue? [Y/n]
then you can have 
./bootstrap.sh 

for interactive installation, but also: 
./bootstrap.sh --all 

to install you entire environment automatically. 

Another feature i'd strongly recommend make it safe to run repeatedly 

for example: 
./bootstrap.sh 

today installs Git. 

Tomorrow you add Docker to the configuration: 
INSTALL_DOCKER=true

then: 
./boostrap.sh

should recognize: 
Git       ✓ already installed
Python    ✓ already installed
Node      ✓ already installed
Docker    → installing
Rust      ✓ already installed

rather than strating from scratch 

