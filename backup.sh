source_dirs=(~/xwt/rn ~/xwt/text ~/xwt/resources ~/xwt/IDMP)
backup_dir=~/.backup
max_file_size="100k"
backup_interval=600 # seconds
backup_retention_period=1440 # minutes

backup_function() {
    # Create backup directory if it doesn't exist
    mkdir -p "$backup_dir"
    
    while true; do
        timestamp=$(date +%Y%m%d_%H%M%S)
        backup_dest="$backup_dir/$timestamp"

        mkdir -p "$backup_dest"

        # Iterate over each source directory and back it up
        for source_dir in "${source_dirs[@]}"; do
            rsync -a --max-size="$max_file_size" "$source_dir" "$backup_dest"
        done

        tar -czvf "$backup_dir/$timestamp.tgz" "$backup_dest"
        rm -rf "$backup_dest"

        # Remove old backups
        find "$backup_dir" -maxdepth 1 -name "*.tgz" -type f -mmin +$backup_retention_period -delete

        sleep $backup_interval
    done
}

start_backup() {
    # Check if backup.sh is already running
    if pgrep -f "backup.sh" | grep -qv $$; then
        echo "Backup process already running."
    else
        backup_function > /dev/null 2>&1 & disown
        backup_pid=$!
        echo "Backup process started."
    fi
}

stop_backup() {
    kill $backup_pid
    echo "Backup process stopped."
}

trap stop_backup HUP

start_backup