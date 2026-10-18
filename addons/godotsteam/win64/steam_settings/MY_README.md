# Local Steam Emulation & Multi-Instance Setup

This document outlines our local Steamworks integration, why we use a custom build of the Goldberg Emulator fork (`gbe_fork` / GSE), how multi-instance isolation works, and how to configure local profiles for development.

---

## 1. Overview: What is `gbe_fork` and Why Do We Use It?

The **GSE Fork** (an enhanced version of the Goldberg Steam Emulator) is a drop-in replacement for Valve's official Steam API library (`libsteam_api.so` on Linux / `steam_api64.dll` on Windows).

### Why We Use It:
* **Offline Local Development:** Simulates Steam lobbies, matchmaking, P2P networking, and player IDs locally without needing a live connection to Valve's servers or running multiple Steam client logins.
* **Rapid Iteration:** Allows launching multiple local game clients on a single development machine to test host/client interactions, disconnects, lobby settings, and synchronization.

---

## 2. The Architectural Challenge & Our C++ Solution

### The GDExtension Load-Order Problem
In Godot 4, GDExtension shared libraries (`.so` / `.dll`) are loaded into process memory by the OS at engine boot **before** any GDScript code executes. 

Standard environment variable tricks (like calling `OS.set_environment("XDG_DATA_HOME", ...)` in GDScript) fail because the C++ emulator evaluates its paths and environment *the exact millisecond the library is loaded*, ignoring subsequent script environment modifications.

### What We Changed in the Emulator C++ Source
We modified `gbe_fork` across three core files (`base.h`, `base.cpp`, `local_storage.cpp` / `settings_parser.cpp`) to implement **Host Process Command-Line Interception**:

1. **Native OS Argument Reading:** On initialization, the emulator reads the OS process command line directly (`/proc/self/cmdline` on Linux, `GetCommandLineW` on Windows, `_NSGetArgv` on macOS).
2. **Flag Detection:** It searches for engine flags—specifically Godot's native `instance=N` argument passed when using editor multi-instance runs.
3. **Automatic Sandbox Routing:** If an instance ID (N) is detected, the emulator automatically isolates itself:
   * **Save Directory:** `~/.local/share/GSE Saves/instance_N/`
   * **Settings Directory:** `steam_settings/instance_N/` (relative to the `.so` file, with a transparent fallback to the base `steam_settings/`)
   * **P2P Listen Port:** `DEFAULT_PORT + N` (prevents local socket binding collisions)
   * **Default Account Name:** `"gse orca N"` (prevents name collisions if no custom profile exists)

---

## 3. Directory Layout

To install the custom emulator build in the project, place the binary and the `steam_settings` folder together inside your GodotSteam addon folder:

```text
your_godot_project/
├── project.godot
├── steam_appid.txt                           # Universal Steam App ID file
└── addons/
    └── godotsteam/                           # GodotSteam GDExtension
        └── linux64/
            ├── libsteam_api.so               # Custom-compiled GSE binary
            └── steam_settings/               # Shared Base Emulator Settings
                ├── configs.app.ini           # Global app flags (optional)
                ├── instance_0/               # Host Profile Overrides
                │   └── configs.user.ini
                ├── instance_1/               # Client 1 Profile Overrides
                │   └── configs.user.ini
                └── instance_2/               # Client 2 Profile Overrides
                    └── configs.user.ini
```

---

## 4. How to Test with Multiple Instances in Godot

Because the binary automatically intercepts command-line arguments, you can use Godot's built-in GUI runner without launcher scripts or external terminal commands.

1. Close the Godot Editor (to release any file locks on the `.so` file).
2. Copy the compiled `libsteam_api.so` into your project's GodotSteam library folder.
3. Open Godot and go to **Debug -> Run Multiple Instances**.
4. Set the instance count (e.g., `2` or `3` instances).
5. Click the standard **Play** button in the top right of the editor.

Godot will spawn child processes passing `instance=0`, `instance=1`, etc. The custom emulator intercepts these arguments on load and isolates each running window automatically.

---

## 5. Adding and Editing Local Profiles

If an `instance_N` folder does not exist, the emulator automatically defaults the account name to `"gse orca N"`. To assign explicit names and Steam IDs for local lobby testing:

### Creating a Profile
Inside `addons/godotsteam/linux64/steam_settings/instance_N/configs.user.ini`, add the following structure:

#### **Host (Instance 0)**
`addons/godotsteam/linux64/steam_settings/instance_0/configs.user.ini`
```ini
[user::general]
account_name=HostPlayer
account_steamid=76561197960287930
language=english
ip_country=US
```

#### **Client 1 (Instance 1)**
`addons/godotsteam/linux64/steam_settings/instance_1/configs.user.ini`
```ini
[user::general]
account_name=ClientPlayer_1
account_steamid=76561197960287931
language=english
ip_country=US
```

#### **Client 2 (Instance 2)**
`addons/godotsteam/linux64/steam_settings/instance_2/configs.user.ini`
```ini
[user::general]
account_name=ClientPlayer_2
account_steamid=76561197960287932
language=english
ip_country=US
```

---

## 6. Supported Command-Line Flags & Environment Variables

If you ever need to run instances via CLI, CI pipelines, or custom launcher scripts, the binary supports the following arguments in order of evaluation priority:

| Priority | Flag / Variable | Description |
| :--- | :--- | :--- |
| **1** | `--gse-instance=N` | Explicit GSE instance ID |
| **2** | `--gse-dir-suffix=S` | Custom directory suffix string |
| **3** | `--gse-save-path=P` / `--gse-settings-path=P` | Direct path overrides |
| **4** | `instance=N` | **Godot Engine Native Multi-Instance Flag** |
| **5** | `--instance=N` / `-instance=N` | Generic CLI fallback |
| **Env** | `GSE_INSTANCE`, `GSE_DIR_SUFFIX` | Environment variable overrides for CI/tooling |
