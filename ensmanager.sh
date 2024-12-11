#!/bin/bash

# Colors for output
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

# Directories and settings
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$BASE_DIR/enshrouded-server"
SERVER_EXECUTABLE="enshrouded_server.exe"

# Wine configuration
export WINEPREFIX="$HOME/.wine/enshrouded_server"

# Check dependencies
check_dependencies() {
    local missing=()
    for dep in "wine" "wget" "tar" "pkill"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}The following dependencies are missing and need to be installed:${RESET}"
        for dep in "${missing[@]}"; do
            echo -e "${YELLOW}- $dep${RESET}"
        done
        echo -e "${RED}Please install the missing dependencies and restart the script.${RESET}"
        exit 1
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
    "$BASE_DIR/steamcmd/steamcmd.sh" +@sSteamCmdForcePlatformType windows +force_install_dir "$SERVER_DIR" +login anonymous +app_update 2278520 validate +quit
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}The server was successfully downloaded.${RESET}"
    else
        echo -e "${RED}Error downloading the server.${RESET}"
    fi
}

# Start server
start_server() {
    echo -e "${CYAN}Starting the server in the background using Wine...${RESET}"
    cd "$SERVER_DIR" || exit
    nohup nice -n -10 wine "$SERVER_EXECUTABLE" > "$BASE_DIR/server.log" 2>&1 &
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Server successfully started in the background.${RESET}"
        echo -e "${YELLOW}Logs are saved in server.log.${RESET}"
    else
        echo -e "${RED}Error starting the server.${RESET}"
    fi
}

# Stop server
stop_server() {
    echo -e "${CYAN}Stopping all processes related to the Enshrouded server...${RESET}"
    pkill -f "$SERVER_EXECUTABLE"
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

# Handle CLI arguments
handle_arguments() {
    case "$1" in
        update)
            download_server
            ;;
        start)
            start_server
            ;;
        stop)
            stop_server
            ;;
        restart)
            restart_server
            ;;
        *)
            echo -e "${RED}Invalid argument: $1${RESET}"
            echo -e "${YELLOW}Usage:${RESET} $0 {update|start|stop|restart}"
            exit 1
            ;;
    esac
}

# Main menu
show_menu() {
    while true; do
        echo -e "${CYAN}-------------------------------------${RESET}"
        echo -e "${CYAN} Enshrouded Server Management Script ${RESET}"
        echo -e "${CYAN}-------------------------------------${RESET}"
        echo -e "${CYAN}Server directory:${RESET} ${YELLOW}$SERVER_DIR${RESET}"
        echo -e "${CYAN}-------------------------------------${RESET}"
        echo -e "${GREEN}1) Download/Update server${RESET}"
        echo -e "${GREEN}2) Start server${RESET}"
        echo -e "${GREEN}3) Stop server${RESET}"
        echo -e "${GREEN}4) Restart server${RESET}"
        echo -e "${GREEN}5) Exit${RESET}"
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
                stop_server
                ;;
            4)
                restart_server
                ;;
            5)
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
