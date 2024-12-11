### Enshrouded Server Management Script

A lightweight Bash script to manage Enshrouded servers using Wine, created as an alternative to Docker. Includes functionality for downloading/updating, starting, stopping, and restarting the server. Works via both an interactive menu and command-line arguments.

#### Features:
- Manages server lifecycle: download, update, start, stop, and restart.
- Logs server output for easier debugging.
- Simple CLI for automation: `./ensmanager.sh start|stop|restart|update`.
- Server configuration is located at `enshrouded-server/enshrouded_server.json`.

#### Notes:
- The server files will be installed in the directory where you run the script.
- The server configuration file is located at `enshrouded-server/enshrouded_server.json`.
- The Wine prefix is located at `~/.wine/enshrouded_server`.

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

Lean and efficient—perfect for those who prefer simplicity over bloated containers.
