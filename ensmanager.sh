#!/bin/bash

# Colors for output
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
RESET="\033[0m"

# Directories and settings
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SERVER_DIR:-$BASE_DIR/enshrouded-server}"
SERVER_EXECUTABLE="enshrouded_server.exe"

# Wine configuration
export WINEPREFIX="$HOME/.wine/enshrouded_server"
mkdir -p "$WINEPREFIX"

# Optional GE-Proton runtime (user-local, no root)
PROTON_TOOLS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/Steam/compatibilitytools.d"
PROTON_LINK="$PROTON_TOOLS_DIR/GE-Proton"
PROTON_DATA_DIR="${PROTON_DATA_DIR:-$BASE_DIR/proton-data}"
STEAM_SDK_DIR="$HOME/.steam/sdk64"

# Advanced dependency check
check_dependencies() {
    local missing=()
    local package_manager=""
    local dependencies=()
    local config_file="$BASE_DIR/.ens_server_manager_config"

    # Detect the package manager
    if command -v apt-get >/dev/null 2>&1; then
        package_manager="apt-get"
        dependencies=("wget" "tar" "wine" "libc6:i386" "libstdc++6:i386" "libncursesw6:i386" "python3" "libfreetype6:i386" "libfreetype6:amd64" "pkill")
    elif command -v zypper >/dev/null 2>&1; then
        package_manager="zypper"
        dependencies=("wget" "tar" "wine" "libX11-6-32bit" "libX11-devel-32bit" "gcc-32bit" "libexpat1-32bit" "libXext6-32bit" "python3" "pkill" "libfreetype6" "libfreetype6-32bit")
    elif command -v dnf >/dev/null 2>&1; then
        package_manager="dnf"
        dependencies=("wget" "tar" "wine" "glibc-devel.i686" "ncurses-devel.i686" "libstdc++-devel.i686" "python3" "freetype" "procps-ng")
    elif command -v pacman >/dev/null 2>&1; then
        package_manager="pacman"
        dependencies=("wget" "tar" "wine" "lib32-libx11" "gcc-multilib" "lib32-expat" "lib32-libxext" "python" "freetype2")
    else
        echo -e "${RED}Error: No supported package manager found on this system.${RESET}"
        exit 1
    fi

    # Check for missing dependencies
    for cmd in "${dependencies[@]}"; do
        if [ "$package_manager" == "apt-get" ] && [[ "$cmd" == *:i386* || "$cmd" == *:amd64* ]]; then
            if ! dpkg-query -W -f='${Status}' "$cmd" 2>/dev/null | grep -q "install ok installed"; then
                missing+=("$cmd")
            fi
        elif [ "$package_manager" == "zypper" ]; then
            if ! rpm -q "${cmd}" >/dev/null 2>&1 && ! command -v "${cmd}" >/dev/null 2>&1; then
                missing+=("$cmd")
            fi
        elif [ "$package_manager" == "dnf" ]; then
            if ! rpm -q "${cmd}" >/dev/null 2>&1 && ! command -v "${cmd}" >/dev/null 2>&1; then
                missing+=("$cmd")
            fi
        elif [ "$package_manager" == "pacman" ]; then
            if ! pacman -Qi "${cmd}" >/dev/null 2>&1 && ! ldconfig -p | grep -q "${cmd}"; then
                missing+=("$cmd")
            fi
        elif [ "$cmd" == "pkill" ]; then
            if ! command -v pkill >/dev/null 2>&1; then
                missing+=("procps")
            fi
        else
            if ! command -v "${cmd}" >/dev/null 2>&1; then
                missing+=("$cmd")
            fi
        fi
    done

    # Report missing dependencies and ask to continue
    if [ ${#missing[@]} -ne 0 ]; then
        # Check if the user has chosen to suppress warnings
        if [ -f "$config_file" ] && grep -q "SUPPRESS_DEPENDENCY_WARNINGS=true" "$config_file"; then
            echo -e "${YELLOW}Continuing despite missing dependencies (warnings suppressed)...${RESET}"
            return
        fi

        echo -e "${RED}Warning: The following required packages are missing: ${missing[*]}${RESET}"
        echo -e "${CYAN}Please install them using the appropriate command for your system:${RESET}"
        case $package_manager in
            "apt-get")
                echo -e "${MAGENTA}sudo dpkg --add-architecture i386${RESET}"
                echo -e "${MAGENTA}sudo apt update${RESET}"
                echo -e "${MAGENTA}sudo apt-get install ${YELLOW}${missing[*]}${RESET}"
                ;;
            "zypper")
                echo -e "${MAGENTA}sudo zypper install ${YELLOW}${missing[*]}${RESET}"
                ;;
            "dnf")
                echo -e "${MAGENTA}sudo dnf install ${YELLOW}${missing[*]}${RESET}"
                ;;
            "pacman")
                echo -e "${BLUE}For Arch Linux users:${RESET}"
                echo -e "${CYAN}1. Edit the pacman configuration file:${RESET}"
                echo -e "   ${MAGENTA}sudo nano /etc/pacman.conf${RESET}"
                echo
                echo -e "${CYAN}2. Find and uncomment the following lines to enable the multilib repository:${RESET}"
                echo -e "   ${GREEN}[multilib]${RESET}"
                echo -e "   ${GREEN}Include = /etc/pacman.d/mirrorlist${RESET}"
                echo
                echo -e "${CYAN}3. Save the file and exit the editor${RESET}"
                echo
                echo -e "${CYAN}4. Update the package database:${RESET}"
                echo -e "   ${MAGENTA}sudo pacman -Sy${RESET}"
                echo
                echo -e "${CYAN}5. Install the missing packages:${RESET}"
                echo -e "   ${MAGENTA}sudo pacman -S ${YELLOW}${missing[*]}${RESET}"
                ;;
        esac

        echo -e "\n"
        echo -e "${YELLOW}Continue anyway?${RESET} ${RED}(not recommended)${RESET} ${YELLOW}[y/N]${RESET}"
        read -r response
        if [[ ! $response =~ ^[Yy]$ ]]; then
            echo -e "${RED}Exiting due to missing dependencies.${RESET}"
            exit 1
        fi

        echo
        echo -e "${YELLOW}Do you want to suppress this warning in the future? [y/N]${RESET}"
        read -r suppress_response
        if [[ $suppress_response =~ ^[Yy]$ ]]; then
            echo "SUPPRESS_DEPENDENCY_WARNINGS=true" >> "$config_file"
            echo -e "${GREEN}Dependency warnings will be suppressed in future runs.${RESET}"
        fi

        echo -e "${YELLOW}Continuing despite missing dependencies...${RESET}"
    fi
}

# Download and prepare SteamCMD
setup_steamcmd() {
    local steamcmd_dir="$BASE_DIR/steamcmd"
    local steamcmd_url="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
    if [ ! -f "$steamcmd_dir/steamcmd.sh" ]; then
        echo -e "${CYAN}Downloading SteamCMD...${RESET}"
        mkdir -p "$steamcmd_dir"
        wget -q -O "$steamcmd_dir/steamcmd_linux.tar.gz" "$steamcmd_url"
        tar -xzf "$steamcmd_dir/steamcmd_linux.tar.gz" -C "$steamcmd_dir"
        rm "$steamcmd_dir/steamcmd_linux.tar.gz"
        echo -e "${GREEN}SteamCMD successfully downloaded.${RESET}"
    else
        echo -e "${GREEN}SteamCMD is already present.${RESET}"
    fi
}

# Download server
download_server() {
    setup_steamcmd
    echo -e "${CYAN}Starting the download of the Enshrouded server...${RESET}"
    mkdir -p "$SERVER_DIR"
    "$BASE_DIR/steamcmd/steamcmd.sh" +@sSteamCmdForcePlatformType windows +@sSteamCmdForcePlatformBitness 64 +force_install_dir "$SERVER_DIR" +login anonymous +app_update 2278520 validate +quit
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}The server was successfully downloaded.${RESET}"
    else
        echo -e "${RED}Error downloading the server.${RESET}"
    fi
}

# Start server
start_server() {
    # Check if the server is already running
    if pgrep -f "$SERVER_EXECUTABLE" > /dev/null; then
        echo -e "${YELLOW}The server is already running.${RESET}"
        return
    fi

    echo -e "${CYAN}Starting the server in the background using Wine...${RESET}"
    cd "$SERVER_DIR" || exit
    nohup wine "$SERVER_EXECUTABLE" > "$BASE_DIR/server.log" 2>&1 &
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Server successfully started in the background.${RESET}"
        echo -e "${YELLOW}Logs are saved in server.log.${RESET}"
    else
        echo -e "${RED}Error starting the server.${RESET}"
    fi
}

# Installed GE-Proton version (resolved symlink target)
proton_installed_version() {
    local target
    target="$(readlink -f "$PROTON_LINK" 2>/dev/null)" || return 1
    [ -n "$target" ] && [ -d "$target" ] || return 1
    basename "$target"
}

# Fetch latest GE-Proton release tag + x86_64 asset URLs
proton_latest_release() {
    local json="$1"
    python3 - "$json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        release = json.load(fh)
except Exception:
    sys.exit(1)

tag = release.get("tag_name", "")
assets = {a.get("name", ""): a.get("browser_download_url", "") for a in release.get("assets", [])}
tarball = f"{tag}-x86_64.tar.gz"
sumfile = f"{tag}-x86_64.sha512sum"
if not tag or tarball not in assets or sumfile not in assets:
    sys.exit(1)
print(tag)
print(assets[tarball])
print(assets[sumfile])
PY
}

# Install or update the latest GE-Proton in the current user's home
install_proton() {
    local force="${1:-}"
    local tmp tag url sumurl installed
    (
    for tool in wget tar python3 sha512sum; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo -e "${RED}Missing tool: $tool${RESET}"
            return 1
        fi
    done

    mkdir -p "$PROTON_TOOLS_DIR" || {
        echo -e "${RED}Cannot create $PROTON_TOOLS_DIR${RESET}"
        return 1
    }
    tmp="$(mktemp -d "$PROTON_TOOLS_DIR/.ge-proton-download.XXXXXX")" || return 1
    trap 'rm -rf "$tmp"' EXIT

    echo -e "${CYAN}Fetching latest GE-Proton release info...${RESET}"
    if ! wget -q -O "$tmp/release.json" "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"; then
        echo -e "${RED}Could not reach the GitHub API (rate limit or no network).${RESET}"
        return 1
    fi
    if ! mapfile -t release < <(proton_latest_release "$tmp/release.json"); then
        echo -e "${RED}Could not parse the latest GE-Proton release.${RESET}"
        return 1
    fi
    tag="${release[0]}"
    url="${release[1]}"
    sumurl="${release[2]}"
    if [ -z "$tag" ] || [ -z "$url" ] || [ -z "$sumurl" ]; then
        echo -e "${RED}Could not parse the latest GE-Proton release.${RESET}"
        return 1
    fi

    installed="$(proton_installed_version 2>/dev/null)"
    if [ "$installed" = "$tag" ] && [ "$force" != "--force" ]; then
        echo -e "${GREEN}GE-Proton $tag is already installed and current.${RESET}"
        echo -e "${CYAN}Path:${RESET} $PROTON_LINK"
        return 0
    fi

    if [ -n "$installed" ]; then
        echo -e "${CYAN}Updating GE-Proton $installed -> $tag${RESET}"
    else
        echo -e "${CYAN}Installing GE-Proton $tag (user: $USER)${RESET}"
    fi
    echo -e "${YELLOW}Download size is about 2 GB.${RESET}"

    if ! wget --progress=dot:giga -O "$tmp/${tag}-x86_64.tar.gz" "$url"; then
        echo -e "${RED}Download of $tag failed.${RESET}"
        return 1
    fi
    if ! wget -q -O "$tmp/${tag}-x86_64.sha512sum" "$sumurl"; then
        echo -e "${RED}Download of the checksum failed.${RESET}"
        return 1
    fi

    echo -e "${CYAN}Verifying checksum...${RESET}"
    if ! (cd "$tmp" && sha512sum -c "${tag}-x86_64.sha512sum" >/dev/null 2>&1); then
        echo -e "${RED}Checksum mismatch - aborting.${RESET}"
        return 1
    fi

    echo -e "${CYAN}Extracting...${RESET}"
    mkdir -p "$tmp/unpacked" || return 1
    if ! tar -xzf "$tmp/${tag}-x86_64.tar.gz" -C "$tmp/unpacked" --strip-components=1; then
        echo -e "${RED}Extraction failed.${RESET}"
        return 1
    fi
    if [ ! -x "$tmp/unpacked/proton" ]; then
        echo -e "${RED}Extracted archive does not contain the proton launcher.${RESET}"
        return 1
    fi

    # Install versioned, then atomically repoint the stable symlink.
    rm -rf "${PROTON_TOOLS_DIR:?}/$tag"
    if ! mv "$tmp/unpacked" "$PROTON_TOOLS_DIR/$tag"; then
        echo -e "${RED}Could not install to $PROTON_TOOLS_DIR/$tag${RESET}"
        return 1
    fi
    ln -sfn "$tag" "$PROTON_LINK"

    echo -e "${GREEN}GE-Proton $tag installed.${RESET}"
    echo -e "${CYAN}Launcher:${RESET} $PROTON_LINK/proton"
    if [ -n "$installed" ] && [ "$installed" != "$tag" ]; then
        echo -e "${YELLOW}Previous version kept at $PROTON_TOOLS_DIR/$installed (remove manually if not needed).${RESET}"
    fi
    )
}

# Ensure Proton can find the native Steam client library
ensure_steam_sdk() {
    local lib="$BASE_DIR/steamcmd/linux64/steamclient.so"
    if [ ! -f "$lib" ]; then
        setup_steamcmd
    fi
    if [ ! -f "$lib" ]; then
        echo -e "${RED}SteamCMD's linux64/steamclient.so is missing.${RESET}"
        echo -e "${YELLOW}Run the server download once so SteamCMD initializes itself.${RESET}"
        return 1
    fi

    mkdir -p "$STEAM_SDK_DIR" || return 1
    if [ ! -e "$STEAM_SDK_DIR/steamclient.so" ]; then
        [ -L "$STEAM_SDK_DIR/steamclient.so" ] && rm -f "$STEAM_SDK_DIR/steamclient.so"
        ln -sfn "$lib" "$STEAM_SDK_DIR/steamclient.so" || return 1
        echo -e "${GREEN}Linked Steam client library for Proton: $STEAM_SDK_DIR/steamclient.so${RESET}"
    fi
}

# Check for the virtual X server required by Proton's launcher
require_xvfb() {
    if command -v xvfb-run >/dev/null 2>&1; then
        return 0
    fi
    echo -e "${RED}xvfb-run is required to start the server with GE-Proton.${RESET}"
    echo -e "${CYAN}Install it for your distribution:${RESET}"
    echo -e "  ${MAGENTA}Debian/Ubuntu:${RESET} sudo apt-get install xvfb"
    echo -e "  ${MAGENTA}openSUSE:${RESET}      sudo zypper install xvfb-run"
    echo -e "  ${MAGENTA}Fedora:${RESET}        sudo dnf install xorg-x11-server-Xvfb"
    echo -e "  ${MAGENTA}Arch:${RESET}          sudo pacman -S xorg-server-xvfb"
    return 1
}

# Shared checks before launching Proton
prepare_proton_start() {
    if [ ! -f "$SERVER_DIR/$SERVER_EXECUTABLE" ]; then
        echo -e "${RED}Server files not found. Run \"$0 update\" first.${RESET}"
        return 1
    fi
    if [ ! -x "$PROTON_LINK/proton" ]; then
        echo -e "${RED}GE-Proton is not installed. Run \"$0 install-proton\" first.${RESET}"
        return 1
    fi
    require_xvfb || return 1
    ensure_steam_sdk || return 1
    mkdir -p "$PROTON_DATA_DIR" || return 1
}

# Start server with GE-Proton (optional runtime)
start_proton() {
    if pgrep -f "$SERVER_EXECUTABLE" > /dev/null; then
        echo -e "${YELLOW}The server is already running.${RESET}"
        return
    fi
    prepare_proton_start || return 1

    echo -e "${CYAN}Starting the server in the background using $(proton_installed_version 2>/dev/null || echo "GE-Proton")...${RESET}"
    (
        cd "$SERVER_DIR" || exit 1
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$BASE_DIR/steamcmd"
        export STEAM_COMPAT_DATA_PATH="$PROTON_DATA_DIR"
        export PROTON_USE_XALIA=0
        unset DISPLAY
        nohup xvfb-run -a "$PROTON_LINK/proton" run "./$SERVER_EXECUTABLE" > "$BASE_DIR/server.log" 2>&1 &
    )
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Server start initiated.${RESET}"
        echo -e "${YELLOW}Logs are saved in server.log.${RESET}"
        echo -e "${YELLOW}The first start creates the Proton prefix and can take a minute.${RESET}"
    else
        echo -e "${RED}Error starting the server.${RESET}"
        return 1
    fi
}

# Stop server (SIGINT -> graceful save, then TERM/KILL as fallback)
stop_server() {
    echo -e "${CYAN}Stopping all processes related to the Enshrouded server...${RESET}"
    if ! pgrep -f "$SERVER_EXECUTABLE" >/dev/null; then
        echo -e "${YELLOW}The server is not running.${RESET}"
        return
    fi

    pkill -INT -f "$SERVER_EXECUTABLE" 2>/dev/null
    local waited=0
    while pgrep -f "$SERVER_EXECUTABLE" >/dev/null && [ $waited -lt 75 ]; do
        sleep 1
        waited=$((waited + 1))
    done

    if pgrep -f "$SERVER_EXECUTABLE" >/dev/null; then
        echo -e "${YELLOW}Graceful shutdown timed out, sending SIGTERM...${RESET}"
        pkill -TERM -f "$SERVER_EXECUTABLE" 2>/dev/null
        sleep 5
    fi
    if pgrep -f "$SERVER_EXECUTABLE" >/dev/null; then
        echo -e "${RED}Processes still alive, sending SIGKILL.${RESET}"
        pkill -KILL -f "$SERVER_EXECUTABLE" 2>/dev/null
        sleep 1
    fi

    if pgrep -f "$SERVER_EXECUTABLE" >/dev/null; then
        echo -e "${RED}Some server processes could not be stopped. Please check manually.${RESET}"
    else
        echo -e "${GREEN}Server successfully stopped.${RESET}"
    fi
}

# Restart server
restart_server() {
    echo -e "${CYAN}Restarting the server...${RESET}"
    stop_server
    sleep 2
    start_server
}

# Restart server with GE-Proton
restart_proton() {
    echo -e "${CYAN}Restarting the server with GE-Proton...${RESET}"
    stop_server
    sleep 2
    start_proton
}

# Find the Windows server process (comm is truncated to "enshrouded_serv")
find_server_pid() {
    local p
    for p in $(pgrep -f "$SERVER_EXECUTABLE" 2>/dev/null); do
        case "$(cat "/proc/$p/comm" 2>/dev/null)" in
            enshrouded*) echo "$p"; return 0 ;;
        esac
    done
    return 1
}

# Run server in the foreground (systemd); SIGTERM/SIGINT -> graceful save
run_server() {
    if pgrep -f "$SERVER_EXECUTABLE" > /dev/null; then
        echo -e "${YELLOW}The server is already running.${RESET}"
        return 1
    fi
    prepare_proton_start || return 1

    echo -e "${CYAN}Starting the server in the foreground using $(proton_installed_version 2>/dev/null || echo "GE-Proton")...${RESET}"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$BASE_DIR/steamcmd"
    export STEAM_COMPAT_DATA_PATH="$PROTON_DATA_DIR"
    export PROTON_USE_XALIA=0
    unset DISPLAY
    cd "$SERVER_DIR" || return 1

    xvfb-run -a "$PROTON_LINK/proton" run "./$SERVER_EXECUTABLE" &
    local launcher_pid=$!
    local app_pid=""
    local i
    for i in $(seq 1 180); do
        app_pid="$(find_server_pid)" && break
        kill -0 "$launcher_pid" 2>/dev/null || break
        sleep 1
    done
    if [ -z "$app_pid" ]; then
        echo -e "${RED}Server process did not start.${RESET}"
        wait "$launcher_pid" 2>/dev/null
        return 1
    fi
    echo -e "${GREEN}Server running (PID $app_pid). Send SIGINT/SIGTERM for a graceful stop.${RESET}"

    trap 'kill -INT "$app_pid" 2>/dev/null' INT TERM
    while kill -0 "$app_pid" 2>/dev/null; do
        sleep 2
    done
    wait "$launcher_pid" 2>/dev/null
    echo -e "${CYAN}Server exited.${RESET}"
}

# Handle CLI arguments
handle_arguments() {
    case "$1" in
        update)
            download_server
            ;;
        start)
            start_server
            ;;
        start-proton)
            start_proton
            ;;
        stop)
            stop_server
            ;;
        restart)
            restart_server
            ;;
        restart-proton)
            restart_proton
            ;;
        run|foreground)
            run_server
            ;;
        install-proton|update-proton)
            install_proton
            ;;
        *)
            echo -e "${RED}Invalid argument: $1${RESET}"
            echo -e "${YELLOW}Usage:${RESET} $0 {update|start|start-proton|stop|restart|restart-proton|run|install-proton|update-proton}"
            exit 1
            ;;
    esac
}

# Main menu
show_menu() {
    while true; do
        local proton_version
        proton_version="$(proton_installed_version 2>/dev/null)"
        echo -e "${CYAN}-------------------------------------${RESET}"
        echo -e "${CYAN} Enshrouded Server Management Script ${RESET}"
        echo -e "${CYAN}-------------------------------------${RESET}"
        echo -e "${CYAN}Server directory:${RESET} ${YELLOW}$SERVER_DIR${RESET}"
        echo -e "${CYAN}GE-Proton:${RESET}        ${YELLOW}${proton_version:-not installed}${RESET}"
        echo -e "${CYAN}-------------------------------------${RESET}"
        echo -e "${GREEN}1) Download/Update server${RESET}"
        echo -e "${GREEN}2) Start server (Wine)${RESET}"
        echo -e "${GREEN}3) Start server (GE-Proton)${RESET}"
        echo -e "${GREEN}4) Stop server${RESET}"
        echo -e "${GREEN}5) Restart server (Wine)${RESET}"
        echo -e "${GREEN}6) Restart server (GE-Proton)${RESET}"
        echo -e "${GREEN}7) Install/Update GE-Proton${RESET}"
        echo -e "${GREEN}8) Exit${RESET}"
        echo -e "${CYAN}-------------------------------------${RESET}"
        read -rp "Choose an option: " choice

        case $choice in
            1)
                download_server
                ;;
            2)
                start_server
                ;;
            3)
                start_proton
                ;;
            4)
                stop_server
                ;;
            5)
                restart_server
                ;;
            6)
                restart_proton
                ;;
            7)
                install_proton
                ;;
            8)
                echo -e "${CYAN}Exiting the script.${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option, please try again.${RESET}"
                ;;
        esac
    done
}

# Main program
check_dependencies
if [ $# -gt 0 ]; then
    handle_arguments "$1"
else
    show_menu
fi
