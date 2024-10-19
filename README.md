# Bulk Rebuild Script

This script rebuilds packages in Koji. It checks for updates, resets builds if necessary, regenerates the repo, and rebuilds packages in batches.

## Usage

`./bulk_rebuild.sh --rebuild-list <package_list_file> --target <target> [--patch-size <num>]`

### Required Arguments

- `--rebuild-list`: Path to a file containing the list of packages to rebuild (one package per line)
- `--target`: Koji build target (e.g., f41-build-side-1)

### Optional Arguments

- `--patch-size`: Number of packages to build before regenerating the repo (default: 5)

## Example

`sh ./bulk_rebuild.sh --rebuild-list shuf_rpm.txt --target f41-build-side-1 --patch-size 20`

## Notes

- It's recommended to `shuf` the package list before running the script.

