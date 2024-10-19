#!/bin/bash

# Default values
PATCH_SIZE=5

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --rebuild-list)
        REBUILD_LIST="$2"
        shift; shift
        ;;
        --patch-size)
        PATCH_SIZE="$2"
        shift; shift
        ;;
        --target)
        TARGET="$2"
        shift; shift
        ;;
        *)    # unknown option
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

# Check if required arguments are provided
if [ -z "$REBUILD_LIST" ] || [ -z "$TARGET" ]; then
    echo "Error: Both --rebuild-list and --target are required."
    echo "Usage: $0 --rebuild-list <package_list_file> --target <target> [--patch-size <num>]"
    exit 1
fi

# Check if the file exists
if [ ! -f "$REBUILD_LIST" ]; then
    echo "Error: The file '$REBUILD_LIST' does not exist."
    exit 1
fi

log_message() {
    local level="$1"
    local message="$2"
    echo "[$level|$(date +%Y-%m-%d/%H:%M:%S)] $message"
}

echo "Starting bulk rebuild with the following parameters:"
log_message "INFO" "Target: $TARGET"
log_message "INFO" "Patch Size: $PATCH_SIZE"
log_message "INFO" "Rebuild List: $REBUILD_LIST"

# If latest SHA matches the current build, reset the build
# Returns 1 if the package doesn't have a build or latest SHA
# ResetBuild is needed because the second build for an existing NVR will fail
resetBuild() {
    package_name=$1

    log_message "INFO" "Checking $package_name..."

    # Fetch all builds for the package
    builds=$(koji -p openkoji list-builds --package=$package_name --source=*src.fedoraproject.org* --pattern=*fc41 --quiet --state=COMPLETE | awk '{print $1}')

    if [ -z "$builds" ]; then
        log_message "INFO" "No builds found for $package_name, skipping..."
        return 1
    fi

    # Get the latest SHA from src.fedoraproject.org
    latestSHA=$(git ls-remote https://src.fedoraproject.org/rpms/$package_name.git | grep refs/heads/f41 | awk '{print $1}')
    if [ -z "$latestSHA" ]; then
        log_message "INFO" "No latest SHA found for $package_name, skipping..."
        return 1
    fi

    # Check if the current builds have the latest SHA
    for build in $builds; do
        currentSHA=$(koji -p openkoji buildinfo $build | awk '/^Source:/ {print $2}' | cut -d'#' -f2)
        # If SHAs match, then reset the build
        if [ "$currentSHA" == "$latestSHA" ]; then
            log_message "INFO" "Resetting build $build for $package_name..."
            command="koji -p openkoji call resetBuild $build"
            log_message "INFO" "$command"
            $command
            return 0
        fi
    done

    return 0
}

# Build the package with the latest SHA from src.fedoraproject.org
buildPackage() {
    package_name=$1
    latestSHA=$(git ls-remote https://src.fedoraproject.org/rpms/$package_name.git | grep refs/heads/f41 | awk '{print $1}')
    SCM_URI="https://src.fedoraproject.org/rpms/$package_name.git#$latestSHA"

    log_message "INFO" "Building $package_name with SHA $latestSHA..."
    COMMAND="koji -p openkoji build --nowait $TARGET git+$SCM_URI"
    log_message "INFO" "$COMMAND"
    OUTPUT=$($COMMAND)

    REGEX='Created task: ([0-9]+)'
    if [[ $OUTPUT =~ $REGEX ]]; then
        TASK_ID=${BASH_REMATCH[1]}
        log_message "INFO" "Task ID: $TASK_ID"
    else
        log_message "ERROR" "Failed to build $package_name: $OUTPUT"
    fi
}

# Regen-repo and wait for completion
# There'll be problems with Koji if packages are built without regen-repo
# So wait is required
regenerate_repo() {
    log_message "INFO" "Regenerating repo..."
    command="koji -p openkoji regen-repo $TARGET --wait"
    log_message "INFO" "$command"
    $command
    if [ $? -eq 0 ]; then
        log_message "INFO" "Repo regeneration completed successfully."
    else
        log_message "ERROR" "Repo regeneration failed. Exiting."
        exit 1
    fi
}

packages_to_build=()

# For each package
while read -r package; do
    # Skip if the package doesn't have a build or latest SHA
    if resetBuild "$package"; then
        packages_to_build+=("$package")

        # Regenerate repo if patch size limit is reached
        if [ ${#packages_to_build[@]} -ge $PATCH_SIZE ]; then
            regenerate_repo
            # Build all packages in the current patch
            for pkg in "${packages_to_build[@]}"; do
                buildPackage "$pkg"
            done
            packages_to_build=()
        fi
    fi
done < "$REBUILD_LIST"

# Final regen-repo and build if needed
if [ ${#packages_to_build[@]} -gt 0 ]; then
    regenerate_repo
    for pkg in "${packages_to_build[@]}"; do
        buildPackage "$pkg"
    done
fi

log_message "INFO" "Script complete."
