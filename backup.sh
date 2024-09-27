#!/bin/bash

# This script performs regular backups of specified directories, manages backup retention,
# and provides functionality to start and stop the backup process.

# Define the directories to be backed up
source_dirs=(~/code ~/data)

# Set the destination directory for backups
backup_dir=~/.backups

# Set the maximum file size for backup (10MB)
max_file_size=10M

# Set the interval between backups (600 seconds = 10 minutes)
backup_interval=600 # seconds

# Set the minimum disk space required to perform backup (in KB)
min_free_space=1000000 # KB

# Set the retention periods for backups
# First value: 1440 minutes (24 hours) - time period in which all backups are retained and time span for each time bin
# Second value: 525600 minutes (1 year) - maximum age of backups
backup_retention_period=(1440 525600) # minutes

# Function to check if there's enough free space in the backup directory
check_space() {
    if [ $(df -P "$backup_dir" | awk 'NR==2 {print $4}') -lt $min_free_space ]; then
        echo "Insufficient free space. Aborting this backup."
        return 1  # Indicate failure
    fi
    return 0  # Indicate success
}

# Function to format date-time string from zip listing to a standard format
format_datetime() {
    input_datetime="$1"  # Get the input date-time as the first argument

    # Extract day, month abbreviation, year (two digits), and time
    year_two_digits=$(echo "$input_datetime" | cut -d'-' -f1)
    month_abbr=$(echo "$input_datetime" | cut -d'-' -f2)
    day=$(echo "$input_datetime" | cut -d'-' -f3 | cut -d' ' -f1)
    time=$(echo "$input_datetime" | cut -d' ' -f2)

    # Convert month abbreviation to month number
    case "$month_abbr" in
        Jan) month_num="01" ;;
        Feb) month_num="02" ;;
        Mar) month_num="03" ;;
        Apr) month_num="04" ;;
        May) month_num="05" ;;
        Jun) month_num="06" ;;
        Jul) month_num="07" ;;
        Aug) month_num="08" ;;
        Sep) month_num="09" ;;
        Oct) month_num="10" ;;
        Nov) month_num="11" ;;
        Dec) month_num="12" ;;
        *) echo "Invalid month abbreviation" ;;
    esac

    # Construct the full year (assuming 21st century for two-digit years)
    full_year="20${year_two_digits}"

    # Format the output date-time
    output_datetime="${full_year}-${month_num}-${day} ${time}"

    echo "$output_datetime" 
}

# Function to perform the actual backup
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

    # Archive the backup into a .tar file
    echo "Creating: $timestamp.tar"
    tar -cvf "$backup_dir/$timestamp.tar" "$backup_dest"
    
    # Check if the backup zip file exists and handle accordingly
    if [ ! -f "$backup_dir/backups.zip" ]; then
        # If the backup file does not exist, create a new one
        zip "$backup_dir/backups.zip" "$backup_dir/$timestamp.tar"
    else
        # If the backup file exists, append the new file to it
        zip -u "$backup_dir/backups.zip" "$backup_dir/$timestamp.tar"
    fi
    
    # Remove the temporary backup directory and tar file
    rm -rf "$backup_dest"
    rm -rf "$backup_dir/$timestamp.tar"
}

# Function to clean up old backups based on retention policy
cleanup_backup() {
    # List the contents of the zip file
    zip_contents=$(unzip -Zs "$backup_dir/backups.zip")
    n_line=$(echo "$zip_contents" | wc -l)
    file_datetime=$(echo "$zip_contents" | awk -v n_line="$n_line" 'NR > 2 && NR < n_line {print $7 " " $8}')
    file_name=$(echo "$zip_contents" | awk -v n_line="$n_line" 'NR > 2 && NR < n_line {print $9}')

    # Find files older than the maximum retention period (1 year)
    old_files=""
    while read -r name datetime; do
        past_epoch=$(date -d "$(format_datetime "$datetime")" +%s)
        current_epoch=$(date +%s)
        minutes_ago=$(( (current_epoch - past_epoch) / 60 ))
        if (( $minutes_ago > ${backup_retention_period[1]} )); then
            old_files="$old_files $name"
        fi
    done < <(paste -d ' ' <(echo "$file_name") <(echo "$file_datetime"))

    # Assign backups to time bins for retention policy
    time_bins=()
    while read -r name datetime; do
        past_epoch=$(date -d "$(format_datetime "$datetime")" +%s)
        current_epoch=$(date +%s)
        minutes_ago=$(( (current_epoch - past_epoch) / 60 ))
        bin=$(( minutes_ago / backup_retention_period[0] ))
        if [ $bin -ge 1 ] && [ $bin -le $((backup_retention_period[1] / backup_retention_period[0] - 1)) ]; then
            time_bins[bin]="${time_bins[bin]}\n$name"
        fi
    done < <(paste -d ' ' <(echo "$file_name") <(echo "$file_datetime"))

    # Implement retention policy for backups between 1 day and 1 year old
    for ((bin=1; bin<=$((backup_retention_period[1] / backup_retention_period[0] - 1)); bin++)); do
        backups_to_filter=$(echo -e "${time_bins[bin]:2}")
        if [ ! -z "$backups_to_filter" ]; then
            # Sort the backups by modification time (oldest first) and keep only the first one
            oldest_backup=$(echo "$backups_to_filter" | sort -n | head -n 1)
            
            # Delete all backups in this range except the oldest one
            for backup in $backups_to_filter; do
                if [ "$backup" != "$oldest_backup" ]; then
                    old_files="$backup $old_files"
                fi
            done
        fi
    done

    # Remove old files from the zip archive
    if [ -n "$old_files" ]; then
        zip -d "$backup_dir/backups.zip" $old_files
    fi
}

# Main loop function for continuous backup
main_loop() {
    # Set up a trap to call stop_backup when the script receives a HUP signal
    trap stop_backup EXIT HUP TERM

    while true; do
        # Log current date and time
        date "+%Y-%m-%d %H:%M:%S"

        # Create backup directory if it doesn't exist
        if [ ! -d "$backup_dir" ]; then
            mkdir -p "$backup_dir" 
        fi

        # Check if disk has enough space and perform backup
        if check_space; then
            perform_backup
        fi

        # Clean up old backups
        cleanup_backup

        # Wait for the specified interval before the next backup
        sleep $backup_interval
    done
}

# Function to start the backup process
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

# Function to stop the backup process
stop_backup() {
    # Log current date and time
    date "+%Y-%m-%d %H:%M:%S"

    # Remove the trap to avoid second trigger by EXIT
    trap '' EXIT HUP TERM

    # Perform final backup before stopping
    if check_space; then
        perform_backup
    fi

    # Stop the backup process
    echo "Backup process stopped."
    exit 0
}

# Start the backup process
start_backup
