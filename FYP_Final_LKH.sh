#!/bin/bash

echo ""
echo ""
echo ""

echo " _______  ______ _______ _____ _______ _______ _______ _______      _______ _______  _____  _     _ _____ _______ _____ _______ _____  _____  __   _      _______  _____   _____        "
echo " |_____| |_____/    |      |   |______ |_____| |          |         |_____| |       |   __| |     |   |   |______   |      |      |   |     | | \  |         |    |     | |     | |     "
echo " |     | |    \_    |    __|__ |       |     | |_____     |         |     | |_____  |____\| |_____| __|__ ______| __|__    |    __|__ |_____| |  \_|         |    |_____| |_____| |_____"
echo ""
echo ""
echo ""
echo "                                                          Forensic Artifact Acquisition Tool"
echo ""
echo ""
echo "                                                             Finding Truth in 1's and 0's."

echo ""
echo ""
echo ""



USB_UUID="8940cbca-b7ee-4d29-9d0b-3c20d101a017"  # Replace with your USB's UUID
USB_LABEL="SSD"  # Replace with your USB's Label (Optional)

# Locate the USB mount point using UUID
USB_PATH=$(findmnt -rn -S UUID=$USB_UUID -o TARGET)

# Fallback: If UUID fails, try using the label
if [ -z "$USB_PATH" ]; then
    USB_PATH=$(findmnt -rn -S LABEL=$USB_LABEL -o TARGET)
fi

# Exit if the USB is not found
if [ -z "$USB_PATH" ]; then
    echo "USB not found! Please ensure it's connected."
    exit 1
fi

# Navigate to USB path and set as BASE_DIR
BASE_DIR="$USB_PATH"
echo "USB detected and mounted at: $USB_PATH"
cd "$USB_PATH" || exit



MEMORY_DUMP_DIR="$BASE_DIR/FYP/memory_dump"  # Define the memory dump directory

LIME_SRC_DIR="$BASE_DIR/FYP/LiME/src"  # Define the LiME source directory




# Function for memory dump creation
linux_triage_memory_dump() {
    echo "Starting memory dump creation..."

    # Create dump directory if it doesn't exist
    mkdir -p "$MEMORY_DUMP_DIR"

    # Check for kernel headers
   # Check if kernel headers are available locally in the default path
KERNEL_VERSION=$(uname -r)
HEADER_PATH="/usr/src/linux-headers-$KERNEL_VERSION"

# Check if kernel headers are available in the default location
if [ -d "$HEADER_PATH" ]; then
    echo "Kernel headers found in $HEADER_PATH"
    # Set the environment variable for the kernel headers location
    export KERNELDIR=$HEADER_PATH
else
    echo "Kernel headers not found in the default location. Attempting to install..."

    # Attempt to install the kernel headers using apt-get
    sudo apt-get install -y linux-headers-$KERNEL_VERSION

    # Recheck if the headers are available after installation
    if [ -d "$HEADER_PATH" ]; then
        echo "Kernel headers installed and found in $HEADER_PATH"
        export KERNELDIR=$HEADER_PATH
    else
        echo "Failed to install kernel headers. Please check your repositories."
        exit 1
    fi
fi

    # Set directory permissions
    echo "Setting directory permissions..."
    sudo chmod -R 755 "$LIME_SRC_DIR"

    # Compile LiME module
    echo "Compiling LiME module..."
    cd "$LIME_SRC_DIR" || exit
    if [ ! -f "Makefile" ]; then
        echo "Creating Makefile..."
        make -C /lib/modules/$(uname -r)/build M="$LIME_SRC_DIR" modules
    else
        echo "Makefile exists, skipping creation."
        make clean
        make -C /lib/modules/$(uname -r)/build M="$LIME_SRC_DIR" modules
    fi

    # Generate a unique filename using the current timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    dump_file="$MEMORY_DUMP_DIR/mem_dump_$timestamp.raw"
    hash_file="$MEMORY_DUMP_DIR/hash_info_$timestamp.txt"  # Separate file for hashes and timing info

    # Record the start time
    start_time=$(date +"%Y-%m-%d %H:%M:%S")
    start_seconds=$(date +%s)

    # Insert LiME kernel module and start memory dump
    echo "Inserting LiME kernel module and starting memory dump..."
    sudo insmod "$LIME_SRC_DIR/lime.ko" "path=$dump_file" "format=raw" "dump=all" "tcp=off"
    
    # Check if the insmod command was successful
    if [ $? -ne 0 ]; then
        echo "Failed to insert LiME module."
        exit 1
    fi

    # Wait for memory dump to complete by checking for the existence of the dump file
    while [ ! -f "$dump_file" ]; do
        echo "Waiting for memory dump to complete..."
        sleep 2  # Check every 2 seconds
    done

    # Check if the dump was created successfully
    if [ -f "$dump_file" ]; then
        echo "Memory dump created successfully at $dump_file."
    else
        echo "Failed to create memory dump."
        exit 1
    fi

    # Generate hashes for the memory dump
    echo "Generating hashes for memory dump..."
    md5_hash=$(md5sum "$dump_file" | awk '{ print $1 }')
    sha1_hash=$(sha1sum "$dump_file" | awk '{ print $1 }')
    sha256_hash=$(sha256sum "$dump_file" | awk '{ print $1 }')

    # Prepare hash output
    hash_output="==================== Hashes and Timings ====================\n"
    hash_output+="Memory dump file: $dump_file\n"
    hash_output+="MD5: $md5_hash\n"
    hash_output+="SHA1: $sha1_hash\n"
    hash_output+="SHA256: $sha256_hash\n"
    hash_output+="Script start time: $start_time\n"
    end_time=$(date +"%Y-%m-%d %H:%M:%S")
    hash_output+="Script end time: $end_time\n"
    end_seconds=$(date +%s)
    total_time=$((end_seconds - start_seconds))
    hash_output+="Total time taken: $total_time seconds\n"
    hash_output+="============================================================\n"

    # Write the hash output to the hash file
    echo -e "$hash_output" > "$hash_file"  # Use > to create/overwrite the hash file

    # Verify that the hash output was written
    if [ $? -eq 0 ]; then
        echo "Hashes and timing information written successfully to $hash_file."
    else
        echo "Failed to write hashes to the hash file."
    fi

    # Remove LiME kernel module
    echo "Removing LiME kernel module..."
    sudo rmmod lime

    # Completion message
    echo "Memory dump and hashes created successfully."
    echo "Memory dump location: $dump_file"
    echo "Hash information location: $hash_file"
}



# Function for artifact extraction
extract_artifacts() {
    echo "Starting artifact extraction..."

    # Get the current timestamp to create a unique directory for each extraction
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ARTIFACT_DIR="$BASE_DIR/FYP/artifacts/$TIMESTAMP"  # Include timestamp in the directory name

    # Create target directories for artifacts inside the timestamped directory
    LOG_DIR="$ARTIFACT_DIR/logs"
    SYSTEM_DIR="$ARTIFACT_DIR/system"
    NETWORK_DIR="$ARTIFACT_DIR/network"
    FILESYSTEM_DIR="$ARTIFACT_DIR/filesystem"
    ACTIVITY_DIR="$ARTIFACT_DIR/activity"
    WEB_DIR="$ARTIFACT_DIR/web"
    OTHER_DIR="$ARTIFACT_DIR/other"

    # Create the timestamped base directory and subdirectories
    mkdir -p "$LOG_DIR" "$SYSTEM_DIR" "$NETWORK_DIR" "$FILESYSTEM_DIR" "$ACTIVITY_DIR" "$WEB_DIR" "$OTHER_DIR"

    # Helper function to copy files and directories with metadata preservation and error handling
    copy_item() {
        local source=$1
        local destination=$2

        if [ -e "$source" ]; then
            if [ -d "$source" ]; then
                cp -r --preserve=all "$source" "$destination"  # Copy directory recursively with metadata
            else
                cp --preserve=all "$source" "$destination"  # Copy file with metadata
            fi
        else
            echo "Source $source does not exist."
        fi
    }

    # Function to ignore certain patterns while copying directories
    ignore_errors() {
        local dir=$1
        local contents=("$@")
        local ignore_list=('lock')

        for item in "${contents[@]:1}"; do
            for ignore in "${ignore_list[@]}"; do
                if [[ $item == *"$ignore"* ]]; then
                    rm -rf "$dir/$item"  # Remove ignored items
                fi
            done
        done
    }

    # Log Artifacts
    copy_item "/var/log/" "$LOG_DIR/"
    copy_item "$HOME" "$ARTIFACT_DIR/user_home"
    copy_item '/var/log/journal' "$LOG_DIR/journal"
    copy_item '/run/log/journal' "$LOG_DIR/journal"

    # System Artifacts
    copy_item '/etc/os-release' "$SYSTEM_DIR"
    copy_item '/etc/issue' "$SYSTEM_DIR"
    copy_item '/etc/passwd' "$SYSTEM_DIR"
    copy_item '/etc/sudoers' "$SYSTEM_DIR"
    copy_item '/var/log/auth.log' "$SYSTEM_DIR"
    copy_item '/etc/hostname' "$SYSTEM_DIR"
    copy_item '/etc/fstab' "$SYSTEM_DIR"
    copy_item '/etc/hostname' "$SYSTEM_DIR"

# User-Specific Configuration Files
copy_item "$HOME/.aws" "$SYSTEM_DIR/aws"
copy_item "$HOME/.config/docker" "$SYSTEM_DIR/docker"
copy_item "$HOME/.ssh" "$SYSTEM_DIR/ssh"
copy_item "$HOME/.gnupg" "$SYSTEM_DIR/gnupg"
copy_item "$HOME/.bashrc" "$ACTIVITY_DIR"
copy_item "$HOME/.zshrc" "$ACTIVITY_DIR"
copy_item "$HOME/.profile" "$ACTIVITY_DIR"

# Application-Specific Logs
copy_item '/var/log/docker' "$LOG_DIR/docker"
copy_item '/var/log/cron' "$LOG_DIR/cron"


    # Save output of various commands to files in SYSTEM_DIR
    {
        echo "=== NTP Status ==="
        if command -v ntpstat &> /dev/null; then
            ntpstat
        else
            echo "NTP daemon is not running."
        fi
        echo "=== Date ==="
        date
        echo "=== CPU Info ==="
        lscpu
        echo "=== Free Memory ==="
        free
        echo "=== IP Tables ==="
        iptables-save
    } > "$SYSTEM_DIR/system_info.txt"

    # Network Artifacts
    {
        echo "=== IP Address ==="
        ip a
        echo "=== IP Route ==="
        ip route
        echo "=== Netstat ==="
        netstat
        echo "=== SS ==="
        ss
        echo "=== LSOF ==="
        lsof -i
        echo "=== ARP ==="
        arp -a
    } > "$NETWORK_DIR/network_info.txt"

    # Copy additional network-related files
    copy_item '/etc/network' "$NETWORK_DIR"
    copy_item '/etc/hosts' "$NETWORK_DIR"
    copy_item '/etc/hosts.allow' "$NETWORK_DIR"
    copy_item '/etc/hosts.deny' "$NETWORK_DIR"

    # Filesystem Artifacts
    {
        echo "=== Block Devices ==="
        lsblk
        echo "=== Disk Partitions ==="
        fdisk -l
        echo "=== Mounted Filesystems ==="
        mount
        echo "=== File System Statistics ==="
        stat /
    } > "$FILESYSTEM_DIR/filesystem_info.txt"

    # Activity Artifacts
    echo "Checking for shell history files..."
    SHELL_HISTORY_FILES=(
        "$HOME/.bash_history"                 # Bash Shell
        "$HOME/.zsh_history"                  # Zsh Shell
        "$HOME/.sh_history"                   # Ksh Shell
        "$HOME/.config/fish/fish_history"     # Fish Shell
    )

    for history_file in "${SHELL_HISTORY_FILES[@]}"; do
        if [ -f "$history_file" ]; then
            echo "Copying $history_file to $ACTIVITY_DIR..."
            copy_item "$history_file" "$ACTIVITY_DIR"
        else
            echo "Source $history_file does not exist."
        fi
    done  # Closing the for loop

    # Web Artifacts
    if [ -d "$HOME/.mozilla/firefox" ]; then
        copy_item "$HOME/.mozilla/firefox" "$WEB_DIR/firefox"
    fi

    if [ -f "/var/log/chrome/chrome.log" ]; then
        copy_item '/var/log/chrome/chrome.log' "$WEB_DIR/chrome"
    fi

    if [ -d "$HOME/.config/google-chrome" ]; then
        copy_item "$HOME/.config/google-chrome" "$WEB_DIR/google-chrome"
    fi

    if [ -d "$HOME/.config/chromium" ]; then
        copy_item "$HOME/.config/chromium" "$WEB_DIR/chromium"
    fi

    if [ -d "$HOME/.config/BraveSoftware/Brave-Browser" ]; then
        copy_item "$HOME/.config/BraveSoftware/Brave-Browser" "$WEB_DIR/brave"
    fi

    if [ -d "$HOME/.config/vivaldi" ]; then
        copy_item "$HOME/.config/vivaldi" "$WEB_DIR/vivaldi"
    fi

    if [ -d "$HOME/.config/opera" ]; then
        copy_item "$HOME/.config/opera" "$WEB_DIR/opera"
    fi

    # Other Artifacts
    if [ -d "/root" ]; then
        copy_item '/root' "$OTHER_DIR"
    else
        echo "Source /root does not exist."
    fi

    # Define directories for storing extracted artifacts
    TEMP_DIR="$ARTIFACT_DIR/tmp"

    # Create target directories if they don't exist
    mkdir -p "$TEMP_DIR"

    # Extract Temporary Files from /tmp and /var/tmp
    TEMP_DIRS=("/tmp" "/var/tmp")
    echo "Extracting temporary files..."
    for DIR in "${TEMP_DIRS[@]}"; do
        if [ -d "$DIR" ]; then
            echo "Copying files from $DIR to $TEMP_DIR..."
            cp -r "$DIR" "$TEMP_DIR/"
        else
            echo "Temporary directory $DIR not found."
        fi
    done

    # Extract Swap Files
    SWAP_FILE="/swap"
    echo "Checking for swap file..."
    if [ -f "$SWAP_FILE" ]; then
        echo "Copying swap file from $SWAP_FILE to $TEMP_DIR..."
        cp "$SWAP_FILE" "$TEMP_DIR/"
    else
        echo "No swap file found."
    fi

    echo "Forensic artifact extraction completed."
}



# Main menu
while true; do
    echo "Select an option:"
    echo "1. Create Memory Dump"
    echo "2. Extract Artifacts"
    echo "3. Exit"
    read -p "Enter choice: " choice
    case $choice in
        1)
            linux_triage_memory_dump
            ;;
        2)
            extract_artifacts
            ;;
        3)
            echo "Exiting."
            exit 0
            ;;
        *)
            echo "Invalid choice, please try again."
            ;;
    esac
done
