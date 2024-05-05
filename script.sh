#!/bin/bash

# Function to display script usage
usage() {
    echo "Usage: $0 [-b <base_url>] [-u <username>] [-p <password>]" 1>&2
    echo "Options:" 1>&2
    echo "  -b <base_url>       qBittorrent base URL (e.g., http://127.0.0.1:8080)" 1>&2
    echo "  -u <username>       qBittorrent username" 1>&2
    echo "  -p <password>       qBittorrent password" 1>&2
    echo "  -m <min_size>       Minimum torrent size in GB (default: 20)" 1>&2
    echo "  -g <min_progress>   Minimum torrent progress in percentage (default: 0.05)" 1>&2
    exit 1
}

# Parse command-line options
while getopts ":b:u:p:m:g:" opt; do
    case ${opt} in
        b)
            QB_BASE_URL_INTERNAL=$OPTARG
            ;;
        u)
            QB_USERNAME_INTERNAL=$OPTARG
            ;;
        p)
            QB_PASSWORD_INTERNAL=$OPTARG
            ;;
        m)
            MIN_SIZE_GB_INTERNAL=$OPTARG
            ;;
        g)
            MIN_PROGRESS_INTERNAL=$OPTARG
            ;;
        *)
            usage
            ;;
    esac
done

# Check if base URL, username, and password are provided as environment variables and override command-line options
if [[ -n $QB_BASE_URL ]]; then
    QB_BASE_URL_INTERNAL=$QB_BASE_URL
fi
if [[ -n $QB_USERNAME ]]; then
    QB_USERNAME_INTERNAL=$QB_USERNAME
fi
if [[ -n $QB_PASSWORD ]]; then
    QB_PASSWORD_INTERNAL=$QB_PASSWORD
fi
if [[ -n $MIN_SIZE_GB ]]; then
    MIN_SIZE_GB_INTERNAL=$MIN_SIZE_GB
fi
if [[ -n $MIN_PROGRESS ]]; then
    MIN_PROGRESS_INTERNAL=$MIN_PROGRESS
fi

# Check if base URL, username, and password are not provided via command-line options
if [[ -z $QB_BASE_URL_INTERNAL || -z $QB_USERNAME_INTERNAL || -z $QB_PASSWORD_INTERNAL ]]; then
    echo "Error: Missing required parameters."
    usage
fi

# Set the default values for minimum size and progress if not provided
if [[ -z $MIN_SIZE_GB_INTERNAL ]]; then
    MIN_SIZE_GB_INTERNAL=20
fi
if [[ -z $MIN_PROGRESS_INTERNAL ]]; then
    MIN_PROGRESS_INTERNAL=0.05
fi

# Function to authenticate via qBittorrent API
authenticate() {
    local response=$(curl -i --data "username=$QB_USERNAME_INTERNAL&password=$QB_PASSWORD_INTERNAL" "$QB_BASE_URL_INTERNAL/api/v2/auth/login")
    local token=$(echo "$response" | grep -i 'set-cookie: SID=' | awk -F'SID=' '{print $2}' | cut -d';' -f1)
    echo "$token"
}

# Function to fetch the list of torrents
get_torrents() {
    local token="$1"
    curl -s -X GET -H "Content-Type: application/json" -H "Cookie: SID=$token" "$QB_BASE_URL_INTERNAL/api/v2/torrents/info"
}

# Function to delete trackers for a specific torrent
delete_trackers() {
    local token="$1"
    local hash="$2"
    local tracker_url="$3"
    curl -s "$QB_BASE_URL_INTERNAL/api/v2/torrents/removeTrackers" -H "content-type: application/x-www-form-urlencoded; charset=UTF-8" -H "Cookie: SID=$token" --data-raw "hash=$hash&urls=$tracker_url"
}

# Main function
main() {
    # Authenticate with qBittorrent
    local token=$(authenticate)
    if [ -z "$token" ]; then
        echo "Failed to authenticate with qBittorrent."
        exit 1
    fi

    # Get the list of torrents
    local torrents=$(get_torrents "$token")
    if [ -z "$torrents" ]; then
        echo "Failed to fetch the list of torrents."
        exit 1
    fi

    # Filter and delete trackers for selected torrents
    echo "$torrents" | jq -c ".[] | select((.total_size / (1024 * 1024 * 1024)) > $MIN_SIZE_GB_INTERNAL and (.progress >= $MIN_PROGRESS_INTERNAL and .progress < 1))" | while IFS= read -r torrent; do
        hash=$(echo "$torrent" | jq -r '.hash')
        name=$(echo "$torrent" | jq -r '.name')
        tracker_url=$(echo "$torrent" | jq -r '.tracker')

        size_bytes=$(echo "$torrent" | jq -r '.total_size')
        size_gb=$(echo "scale=2; $size_bytes / (1024 * 1024 * 1024)" | bc)

        echo "Deleting tracker: $name ($size_gb GB) - $tracker_url"
        if [ -z "$tracker_url" ]; then
            continue
        fi

        # Call delete_trackers function to delete trackers for this torrent
        delete_trackers "$token" "$hash" "$tracker_url"
    done


    # echo "Operation completed successfully."
}

# Execute the main function
main