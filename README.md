# vman — V version manager

Install, switch, and manage multiple V compiler versions.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/SOG-web/vman/main/install.sh | bash
```

Or install manually:

```bash
git clone https://github.com/SOG-web/vman
cd vman
v -cc clang -o vman .
sudo cp vman /usr/local/bin/vman
```

Then add to your shell profile:

```bash
export PATH="$HOME/.vman/current:$PATH"
```

## Usage

```bash
# Install official V from prebuilt binaries
vman --install=0.5.1
vman --install=latest

# Install by building from source
vman --install-src=main

# Switch versions
vman --use=0.5.1

# List installed versions
vman --list

# Show current version
vman --current

# Uninstall
vman --uninstall=0.5.1
```

## Custom forks

Register a fork with its git URL and build commands:

```bash
vman --fork-add=relaxed \
  --url=https://github.com/SOG-web/v \
  --build-cmd="make,./v -cc clang -o vnew cmd/v"
  --fork-bin="vnew"
```

`--build-cmd` takes comma-separated commands that run in order inside the cloned repo. VFLAGS are automatically cleared during builds to prevent conflicts.
`--fork-bin` specifies the binary to use after building, defaults to `v`.

Install and use the fork like any version:

```bash
vman --install=relaxed
vman --use=relaxed
```

Remove a fork registration:

```bash
vman --fork-rm=relaxed
```

### Fork examples

**Fork that only needs `make`:**

```bash
vman --fork-add=stable --url=https://github.com/someone/v-fork --build-cmd="make"
```

**Fork with custom build steps:**

```bash
vman --fork-add=myfork \
  --url=https://github.com/me/my-v-fork \
  --build-cmd="make,./v -cc clang -o vnew cmd/v"
```

**Local fork (no clone needed):**

```bash
vman --fork-add=local --url=/path/to/local/v --build-cmd="make"
```

## Short flags

```
-i <version>   --install
-u <version>   --use
-r <version>   --uninstall
-l             --list
-c             --current
-h             --help
```

## How it works

- Official V releases are downloaded as prebuilt binaries from GitHub releases
- Custom forks are cloned, built with your commands, and stored as full source trees
- Versions are stored in `~/.vman/versions/`
- The active version is symlinked at `~/.vman/current`

## Directory structure

```
~/.vman/
  versions/
    0.5.1/           # V binary at v/v
    relaxed/         # Fork source tree with binary
  current -> ~/.vman/versions/0.5.1/v
  config.json        # Registered forks with URLs and build commands
```
