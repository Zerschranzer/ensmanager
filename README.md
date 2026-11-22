### Enshrouded Server Management Script for Linux

A lightweight Bash script to manage Enshrouded servers using Wine or GE-Proton, created as an alternative to Docker. Includes functionality for downloading/updating, starting, stopping, and restarting the server. Works via both an interactive menu and command-line arguments.

#### Features:
- Manages server lifecycle: download, update, start, stop, and restart.
- Two runtimes: system Wine (default) and optional GE-Proton.
- Installs and updates the latest GE-Proton in the current user's home (no root).
- Graceful stop: SIGINT first so the server writes a save, then TERM/KILL as fallback.
- Logs server output for easier debugging.
- Simple CLI for automation.

#### Notes:
- The server files will be installed in the directory where you run the script.
- The server configuration file is located at `enshrouded-server/enshrouded_server.json`.
- The Wine prefix is located at `~/.wine/enshrouded_server`.
- GE-Proton is installed to `~/.local/share/Steam/compatibilitytools.d/GE-Proton`
  (versioned directory plus symlink); its prefix defaults to `./proton-data`.
- The server log is `server.log` in the script directory.

#### How to Use:
1. Clone the repository:
   ```bash
   git clone https://github.com/Zerschranzer/ensmanager.git
   ```
2. Navigate into the directory:
   ```bash
   cd ensmanager
   ```
3. Make the script executable:
   ```bash
   chmod +x ensmanager.sh
   ```
4. Run the script:
   ```bash
   ./ensmanager.sh
   ```

#### Optional: GE-Proton runtime

GE-Proton is not required. It is useful on hosts where Wine shows server-load
warnings or tick jitter under player load; reports for Enshrouded suggest the
Proton runtime reduces those warnings.

```bash
./ensmanager.sh install-proton      # install the latest GE-Proton (user-local)
./ensmanager.sh update-proton       # update to the latest release
./ensmanager.sh start-proton        # start the server with GE-Proton
./ensmanager.sh restart-proton
```

Requirements:
- `xvfb` (`xvfb-run`); Proton's launcher needs a display even headless.
- `python3`, `wget`, `tar`, `sha512sum` (already used by the script).
- The script links `~/.steam/sdk64/steamclient.so` to SteamCMD's
  `linux64/steamclient.so` on first start. Without it Proton fails with
  `No SteamClient023`.
- The first Proton start creates `./proton-data` and can take a minute.

`stop` works for both runtimes and sends SIGINT first, so the world is saved.

CLI overview:

```bash
./ensmanager.sh update          # server files
./ensmanager.sh start           # Wine
./ensmanager.sh start-proton    # GE-Proton
./ensmanager.sh stop
./ensmanager.sh restart         # Wine
./ensmanager.sh restart-proton  # GE-Proton
./ensmanager.sh install-proton
./ensmanager.sh update-proton
./ensmanager.sh run            # foreground, for systemd
```

`run` keeps the Proton process in the foreground and forwards SIGTERM/SIGINT
to the server as SIGINT, so a service stop still writes a save.

#### systemd (optional)

```ini
[Unit]
Description=Enshrouded Dedicated Server
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/path/to/ensmanager
ExecStart=/path/to/ensmanager/ensmanager.sh run
KillSignal=SIGTERM
TimeoutStopSec=120
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
```

Lean and efficient—perfect for those who prefer simplicity over bloated containers.
