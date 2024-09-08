#!/bin/bash

# Define the directories to be backed up
source_dirs=(~/workdir ~/documents)

# Set the destination directory for backups
backup_dir=~/.backup

# Set the maximum file size for backup (100KB)
max_file_size="100k"

# Set the interval between backups (600 seconds = 10 minutes)
backup_interval=600 # seconds

# Set the retention periods for backups
# First value: 1440 minutes (24 hours)
# Second value: 525600 minutes (1 year)
backup_retention_period=(1440 525600) # minutes

check_space() {
    if [ $(df -P "$backup_dir" | awk 'NR==2 {print $4}') -lt 1000000 ]; then
        echo "Less than 1GB free space. Aborting backup." >&2
        exit 1
    fi
}

backup_function() {
    while true; do
        # Check if disk has enough space
        check_space

        # Create a timestamp for the current backup
        timestamp=$(date +%Y%m%d_%H%M%S)
        backup_dest="$backup_dir/$timestamp"

        # Create a temporary directory for the current backup
        mkdir -p "$backup_dest"

        # Iterate over each source directory and back it up
        for source_dir in "${source_dirs[@]}"; do
            # Use rsync to copy files, excluding those larger than max_file_size
            rsync -a --max-size="$max_file_size" "$source_dir" "$backup_dest"
        done

        # Compress the backup into a .tgz file
        tar -czvf "$backup_dir/$timestamp.tgz" "$backup_dest"
        
        # Remove the temporary backup directory
        rm -rf "$backup_dest"

        # Remove old backups
        # Find backups older than 1 year and delete them
        find "$backup_dir" -type f -name "*.tgz" -mmin +$((backup_retention_period[1])) -delete

        # Implement a retention policy for backups between 1 day and 1 year old
        for ((bin=1; bin<=$((backup_retention_period[1] / backup_retention_period[0] - 1)); bin++)); do
            # Find backups in the current time bin
            backups_to_filter=$(find "$backup_dir" -type f -name "*.tgz" -mmin +$((bin * backup_retention_period[0])) -mmin -$(((bin + 1) * backup_retention_period[0])))

            if [ ! -z "$backups_to_filter" ]; then
                # Sort the backups by modification time (oldest first) and keep only the first one
                oldest_backup=$(echo "$backups_to_filter" | sort -n | head -n 1)
                
                # Delete all backups in this range except the oldest one
                for backup in $backups_to_filter; do
                    if [ "$backup" != "$oldest_backup" ]; then
                        rm $backup
                    fi
                done
            fi
        done

        # Wait for the specified interval before the next backup
        sleep $backup_interval
    done
}

start_backup() {
    # Create backup directory if it doesn't exist
    mkdir -p "$backup_dir"

    # Check if disk has enough space
    check_space

    # Check if backup.sh is already running
    if pgrep -f "backup.sh" | grep -qv $$; then
        echo "Backup process already running."
    else
        # Start the backup function in the background and disown it
        backup_function > /dev/null 2>&1 & disown
        backup_pid=$!
        echo "Backup process started."
    fi
}

stop_backup() {
    # Stop the backup process
    kill $backup_pid
    echo "Backup process stopped."
}

# Set up a trap to call stop_backup when the script receives a HUP signal
trap stop_backup HUP

# Start the backup process
start_backup
