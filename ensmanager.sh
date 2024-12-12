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
mkdir -p "$WINEPREFIX"

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
