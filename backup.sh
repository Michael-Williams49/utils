#!/bin/bash

# Define the directories to be backed up
source_dirs=(~/xwt/rn ~/xwt/text ~/xwt/resources ~/xwt/IDMP)

# Set the destination directory for backups
backup_dir=~/.backups

# Set the maximum file size for backup (100KB)
max_file_size=10M

# Set the interval between backups (600 seconds = 10 minutes)
backup_interval=600 # seconds

# Set the minimum disk space required to perform backup
min_free_space=1000000 # KB

# Set the retention periods for backups
# First value: 1440 minutes (24 hours)
# Second value: 525600 minutes (1 year)
backup_retention_period=(1440 525600) # minutes

check_space() {
    if [ $(df -P "$backup_dir" | awk 'NR==2 {print $4}') -lt $min_free_space ]; then
        echo "Insufficient free space. Aborting this backup."
        return 1  # Indicate failure
    fi
    return 0  # Indicate success
}

perform_backup() {
    # Create a timestamp for the current backup
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_dest="$backup_dir/$timestamp"

    # Create a temporary directory for the current backup
    mkdir "$backup_dest"

    # Iterate over each source directory and back it up
    for source_dir in "${source_dirs[@]}"; do
        # Use rsync to copy files, excluding those larger than max_file_size
        rsync -a --max-size="$max_file_size" "$source_dir" "$backup_dest"
    done

    # Compress the backup into a .tgz file
    echo "Creating: $timestamp.tgz"
    tar -czvf "$backup_dir/$timestamp.tgz" "$backup_dest"
    
    # Remove the temporary backup directory
    rm -rf $backup_dest

    # Remove old backups
    # Find backups older than 1 year and delete them
    backups_to_remove=$(find "$backup_dir" -type f -name "*.tgz" -mmin +${backup_retention_period[1]})
    for backup in $backups_to_remove; do
        echo "Removing: $backup"
        rm $backup
    done

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
                    echo "Removing: $backup"
                    rm $backup
                fi
            done
        fi
    done
}

main_loop() {
    # Set up a trap to call stop_backup when the script receives a HUP signal
    trap stop_backup HUP TERM

    while true; do
        # Log current date and time
        date +%Y-%m-%d_%H:%M:%S

        # Check if disk has enough space
        if check_space; then
            perform_backup
        fi

        # Wait for the specified interval before the next backup
        sleep $backup_interval
    done
}

start_backup() {
    # Create backup directory if it doesn't exist
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir" 
    fi

    # Check if disk has enough space
    check_space

    # Check if backup.sh is already running
    if pgrep -f "backup.sh" | grep -qv $$; then
        echo "Backup process already running."
    else
        # Start the backup function in the background and disown it
        main_loop >> "$backup_dir/logs.txt" 2>&1 & disown
        echo "Backup process started."
    fi
}

stop_backup() {
    # Log current date and time
    date +%Y-%m-%d_%H:%M:%S

    # Perform logout backup
    if check_space; then
        perform_backup
    fi

    # Stop the backup process
    echo "Backup process stopped."
    exit 0
}

# Start the backup process
start_backup
