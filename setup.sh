#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Global variables
MOUNT_DIRECTORY="/media/nas_drives"
MOUNTED_DRIVES_FILE="mounted_drives.txt"
VERBOSE=1
PATH_TO_NAS_SYNCER=""
SCRIPT_OUTPUT="/dev/null"

# Parse command line arguments
parse_args() {
    local positional=()
    for arg in "$@"; do
        case "$arg" in
            -s|--silent)
                VERBOSE=0
                ;;
            *)
                positional+=("$arg")
                ;;
        esac
    done

    PATH_TO_NAS_SYNCER="${positional[0]:-$HOME/rasnas/}"

    if [[ $VERBOSE -eq 1 ]]; then
        SCRIPT_OUTPUT="/dev/stdout"
    else
        echo "installing dependencies quietly. use -v or --verbose to see output."
    fi
}

# Utility functions
print_msg() {
    if [[ ${VERBOSE} -ne 1 ]]; then
        return
    fi
    echo "$@"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Setup functions
setup_pythonpath() {
    unset PYTHONPATH
    print_msg "Setting PYTHONPATH to: $PATH_TO_NAS_SYNCER"
    export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}$PATH_TO_NAS_SYNCER"
}

install_gum() {
    print_msg "Checking for gum installation"
    if ! command_exists gum; then
        print_msg "gum not found. Installing..."
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/charm.gpg
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list >"$SCRIPT_OUTPUT" 2>&1
        sudo apt install -y gum >"$SCRIPT_OUTPUT" 2>&1
    else
        print_msg "gum is already installed."
    fi
}

install_samba() {
    print_msg "Checking for samba installation"
    if ! command_exists samba; then
        print_msg "samba not found. Installing..."
        sudo apt install -y samba >"$SCRIPT_OUTPUT" 2>&1
    else
        print_msg "samba is already installed."
    fi
}

install_uv() {
    print_msg "Checking for uv installation"
    if ! command_exists uv; then
        print_msg "uv not found. Installing..."
        curl -LsSf https://astral.sh/uv/install.sh | sh >"$SCRIPT_OUTPUT" 2>&1
        source "$HOME/.local/bin/env" >"$SCRIPT_OUTPUT" 2>&1
    else
        print_msg "uv is already installed."
    fi
}

install_python() {
    print_msg "Checking for python 3.12 install (via uv)"
    if ! uv python list --only-installed | grep -q "3.12"; then
        print_msg "Python 3.12 not found. Installing with uv..."
        uv python install 3.12 >"$SCRIPT_OUTPUT" 2>&1
    else
        print_msg "Python 3.12 is already installed."
    fi
}

install_dependencies() {
    print_msg "------------- Installing dependencies -------------"
    # repetitive but i dont care
    if ! command_exists samba || ! command_exists gum || ! command_exists curl || ! command_exists tmux; then
        sudo apt update >"$SCRIPT_OUTPUT" 2>&1
    fi
    if ! command_exists curl; then
        sudo apt install -y curl >"$SCRIPT_OUTPUT" 2>&1
    fi
    if ! command_exists tmux; then
        sudo apt install -y tmux >"$SCRIPT_OUTPUT" 2>&1
    fi
    install_gum
    install_samba
    install_uv
    install_python
    print_msg "---------- Done installing dependencies ----------"
}


main_menu() {
    local SETUP_DRIVES=$(gum choose "set up drives" "set up samba" "start server" "kill server" "open server session" "unmount drives" "exit" --header "What would you like to do?")
    clear
    if [[ "$SETUP_DRIVES" == "set up drives" ]]; then
        echo "Continuing with drive setup..."
        local disk_names=()
        local disk_labels=()
        local disk_sizes=()
        local disk_info=()


        while read -r name label size type; do
            # Store partition info and associate with last disk
            disk_names+=("$name")
            disk_labels+=("$label")
            disk_sizes+=("$size")
            disk_info+=("$name,$label,$size")

        done < <(lsblk -o NAME,LABEL,SIZE,TYPE --noheadings| sed 's/└─//g'| grep 'part' | grep -Ev 'bootfs|rootfs')

        local WHICH_DRIVES=""
        while [[ -z "$WHICH_DRIVES" ]]; do
            WHICH_DRIVES=$(gum choose "${disk_info[@]}" --header "which drives to setup? 'x' to select. ctrl-c to exit" --no-limit)
            if [[ -z "$WHICH_DRIVES" ]]; then
                echo "You must select at least one drive. Please try again. ctrl-c to exit"
            fi
        done

        local IFS=$'\n'
        local selected_drives=()
        
        for drive in $WHICH_DRIVES; do
            IFS=',' read -r name label size <<< "$drive"
            selected_drives+=("$name,$label,$size")
        done
        echo
        echo "Selected drives:"
        echo "${selected_drives[*]}"
        if ! gum confirm "Mount these drives?"; then
            echo "Mounting cancelled."
            return
        fi
        echo "Mounting drives..."

        for drive in $WHICH_DRIVES; do
            IFS=',' read -r name label size <<< "$drive"
            sudo mkdir -p "$MOUNT_DIRECTORY/$label"
            sudo mount -o uid=1000,gid=1000,umask=000 /dev/"$name" "$MOUNT_DIRECTORY/$label"
            echo "Mounted /dev/$name to $MOUNT_DIRECTORY/$label"
            sudo chmod -R u+w "$MOUNT_DIRECTORY/$label"
        done

        local PRIMARY_DRIVE=""
        while [[ -z "$PRIMARY_DRIVE" ]]; do
            PRIMARY_DRIVE=$(gum choose "${selected_drives[@]}" --header "which drive to use as primary? The others will be used as backup copies")
            if [[ -z "$PRIMARY_DRIVE" ]]; then
                echo "You must select one primary drive. Please try again. ctrl-c to exit"
            fi
        done

        # Clear mounted_drives.txt before writing
        > mounted_drives.txt
        # Write primary and backup drive labels to mounted_drives.txt
        # Extract label from PRIMARY_DRIVE
        IFS=',' read -r primary_name primary_label primary_size <<< "$PRIMARY_DRIVE"
        echo "$primary_label" > mounted_drives.txt

        # Write backup drive labels
        for drive in "${selected_drives[@]}"; do
            IFS=',' read -r name label size <<< "$drive"
            if [[ "$label" != "$primary_label" ]]; then
                echo "$label" >> mounted_drives.txt
            fi
        done

        echo "all done!"
    elif [[ "$SETUP_DRIVES" == "set up samba" ]]; then
        echo
        if ! gum confirm "Set up samba file share for your drives?"; then
            echo "Samba setup cancelled."
            return
        fi
        if [[ ! -f mounted_drives.txt ]]; then
            echo "perform drive setup first. Exiting."
        else
            echo "Setting up Samba shares..."
            while read -r label; do
                sudo chmod -R 0777 "$MOUNT_DIRECTORY/$label"
                # sudo chown -R nobody:nogroup "$MOUNT_DIRECTORY/$label"
                if ! grep -q "^\[${label}\]" /etc/samba/smb.conf; then
                    echo "[${label}]" | sudo tee -a /etc/samba/smb.conf > /dev/null
                    echo "   path = ${MOUNT_DIRECTORY}/${label}" | sudo tee -a /etc/samba/smb.conf > /dev/null
                    echo "   browseable = yes" | sudo tee -a /etc/samba/smb.conf > /dev/null
                    echo "   writeable = yes" | sudo tee -a /etc/samba/smb.conf > /dev/null
                    echo "   create mask = 0777" | sudo tee -a /etc/samba/smb.conf > /dev/null
                    echo "   directory mask = 0777" | sudo tee -a /etc/samba/smb.conf > /dev/null
                    echo "   public = yes" | sudo tee -a /etc/samba/smb.conf > /dev/null
                else
                    echo "Samba share [${label}] already exists in /etc/samba/smb.conf, skipping."
                fi
            done < mounted_drives.txt
            sudo systemctl restart smbd
            echo "Samba shares set up and restarted."
        fi
        echo "-"
    elif [[ "$SETUP_DRIVES" == "start server" ]]; then
        if ! gum confirm "Start python sync server?"; then
            echo "Server startup cancelled."
            return
        fi
        local session_name="nas-sync-server"
        if tmux has-session -t "$session_name" 2>/dev/null; then
            echo "Tmux session '$session_name' already exists. 'open server session' from the menu to attach to it."
            echo "once attached, 'uv run main.py' if not already running"
            return
        fi
        tmux new-session -d -s "$session_name"
        tmux send-keys -t "$session_name" 'uv run main.py' C-m
        echo "Python sync server started in tmux session '$session_name'. 'start server' from the menu to create it.."
    elif [[ "$SETUP_DRIVES" == "kill server" ]]; then
        if ! gum confirm "Kill python sync server?"; then
            echo "Server startup cancelled."
            return
        fi
        local session_name="nas-sync-server"
        if tmux has-session -t "$session_name" 2>/dev/null; then
            gum spin --spinner dot --title "Killing Python Sync Server..." -- sleep 2
            tmux send-keys -t "$session_name" C-c
            sleep 0.2
            tmux send-keys -t "$session_name" C-c
            sleep 2
            tmux kill-session -t "$session_name"
            echo "killed python sync server in tmux session '$session_name'."
            return
        fi
        echo "There was no session: '$session_name' to kill."
    elif [[ "$SETUP_DRIVES" == "open server session" ]]; then
        local session_name="nas-sync-server"
        if tmux has-session -t "$session_name" 2>/dev/null; then
            tmux a -t "$session_name"
        else
            echo "session '$session_name' does not exist. 'start server' from the menu to create it."
        fi
    elif [[ "$SETUP_DRIVES" == "unmount drives" ]]; then
        echo "-"
        echo "Not implemented yet. Must be done manually for now."
        echo "lsblk -o NAME,MOUNTPOINT"
        echo "and then"
        echo "sudo umount /path/to/mountpoint"
        echo "optionally delete drives from samba on /etc/samba/smb.conf"
        echo "then 'sudo systemctl restart smbd'"
        # for drive in "${selected_drives[@]}"; do
        #     IFS=',' read -r name label size <<< "$drive"
        #     sudo umount /mnt/$label
        #     echo "Unmounted /mnt/$label"
        # done
    else
        echo "Exiting."
    fi
}

clean_up() {
    set +e
    set +u
    set +o pipefail
    unset MOUNT_DIRECTORY MOUNTED_DRIVES_FILE VERBOSE PATH_TO_NAS_SYNCER SCRIPT_OUTPUT
    unset -f parse_args print_msg command_exists setup_pythonpath install_gum install_samba install_uv install_python install_dependencies main_menu main
}       

# Main execution
main() {
    parse_args "$@"
    install_dependencies
    main_menu
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        setup_pythonpath
        clean_up
    fi
}

main "$@"
