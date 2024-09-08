#!/bin/bash

# Check for IP address argument
if [ $# -eq 0 ]; then
  echo "Usage: $0 <IP_address> [<start_port> <end_port> <max_concurrent_processes> <time_out>]"
  exit 1
fi

IP_ADDRESS=$1

# Set default port range if not provided
START_PORT=${2:-1}
END_PORT=${3:-65535}

# Set default maximum concurrent processes
MAX_CONCURRENT=${4:-500}  # Adjust this based on your system
TIME_OUT=${5:-1}

echo "Scanning open ports on $IP_ADDRESS (ports $START_PORT-$END_PORT) with max $MAX_CONCURRENT concurrent processes..."

for port in $(seq $START_PORT $END_PORT); do
    while [ $(jobs -r | wc -l) -ge $MAX_CONCURRENT ]; do
        sleep 0.1  # Wait for some processes to finish
    done

    printf "Scanning port $port\r"    # Print the port number

    timeout $TIME_OUT nc -z $IP_ADDRESS $port &> /dev/null && printf "Port $port is open\033[K\n" &

done

wait

printf "Scan complete.\033[K\n"
