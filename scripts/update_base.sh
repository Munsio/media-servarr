#!/usr/bin/env bash

# This script automates the process of incrementing version numbers in Helm Chart.yaml files and updating specific dependencies.
# It supports major, minor, or patch version increments and updates dependencies to match the root Chart.yaml version.
# Usage: ./script.sh <major|minor|patch>
# Requirements: Bash 4.4 or later, dasel tool for YAML processing.

set -e

# Check for dasel command and exit if not found
if ! command -v dasel &> /dev/null; then
    echo "dasel could not be found. Please install dasel to continue."
    exit 1
fi

# Increment version numbers based on the specified type (major, minor, patch).
# Arguments:
#   version: The current version string (e.g., "1.0.0").
#   type: The type of version increment (major, minor, patch).
# Outputs:
#   Prints the new version string to stdout.
increment_version() {
  local version=$1 type=$2
  local major minor patch IFS=.
  read -r major minor patch <<< "$version"

  case "$type" in
    major)
      ((major++)); minor=0; patch=0 ;;
    minor)
      ((minor++)); patch=0 ;;
    patch)
      ((patch++)) ;;
    *)
      echo "Invalid version type: $type" >&2; exit 1 ;;
  esac

  echo "${major}.${minor}.${patch}"
}

# Read the 'version' field from a Chart.yaml file.
# Arguments:
#   file: Path to the Chart.yaml file to read.
# Outputs:
#   Prints the current version to stdout.
get_chart_version() {
  local file=$1
  dasel query -i yaml "version" < "$file"
}

# Update the version in a Chart.yaml file.
# Arguments:
#   file: Path to the Chart.yaml file to update.
#   new_version: The new version string to apply.
# Outputs:
#   Writes changes to the specified file and logs the action.
update_chart_version() {
  local file=$1 new_version=$2
  echo "Updating version in $file to $new_version"
  sed -i "s/^version:.*/version: ${new_version}/" "$file"
}

# Update a specific dependency version in a Chart.yaml file, if that dependency exists.
# Arguments:
#   file: Path to the Chart.yaml file to update.
#   dependency_name: The name of the dependency to update (e.g., "base", "media-servarr-base").
#   new_version: The new version string for the dependency.
# Outputs:
#   Writes changes to the specified file and logs the action. No-ops (with no error) if
#   the named dependency isn't present in the file.
update_dependency_version() {
  local file=$1 dependency_name=$2 new_version=$3
  local match_result

  # Check if the dependency exists by attempting to get the first match
  # Returns "null" if no match is found
  match_result=$(dasel query -i yaml "dependencies.filter(name == \"${dependency_name}\").first()" < "$file")

  if [[ "$match_result" == "null" ]]; then
    return 0
  fi

  echo "Updating $dependency_name dependency version in $file to $new_version"

  # Write with awk rather than dasel: dasel's write path re-serializes the
  # whole document (reformatting every list's indentation), whereas awk lets
  # us touch only the one "version:" line inside the matching dependency
  # block, leaving the rest of the file byte-for-byte unchanged.
  awk -v name="$dependency_name" -v new_version="$new_version" '
    /^dependencies:/ { in_deps = 1 }
    in_deps && /^[^[:space:]]/ && !/^dependencies:/ { in_deps = 0 }
    in_deps && /^[[:space:]]*- name:/ {
      line = $0
      gsub(/^[[:space:]]*- name:[[:space:]]*/, "", line)
      gsub(/["\x27]/, "", line)
      in_block = (line == name)
    }
    in_deps && in_block && /^[[:space:]]*version:/ {
      sub(/version:.*/, "version: " new_version)
      in_block = 0
    }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# The main function orchestrates the version update process.
# It validates the input, updates the root Chart.yaml version, and then updates versions and dependencies in sub-chart Chart.yaml files.
# Arguments:
#   type: The type of version increment (major, minor, patch).
# Outputs:
#   Writes changes to Chart.yaml files and logs actions to stdout.
main() {
  local type=$1
  local current_version
  local new_version

  if [[ -z "$type" ]]; then
    echo "Usage: $0 <major|minor|patch>"
    exit 1
  fi

  local root_chart="./Chart.yaml"
  if [[ ! -f "$root_chart" ]]; then
    echo "Base Chart.yaml not found."
    exit 1
  fi

  current_version=$(get_chart_version "$root_chart")
  new_version=$(increment_version "$current_version" "$type")

  update_chart_version "$root_chart" "$new_version"

  echo "Base Chart.yaml updated from $current_version to $new_version"

  find charts -type f -name Chart.yaml | while read -r chart; do
    local sub_current_version
    local sub_new_version

    sub_current_version=$(get_chart_version "$chart")
    sub_new_version=$(increment_version "$sub_current_version" "$type")

    update_chart_version "$chart" "$sub_new_version"
    update_dependency_version "$chart" "base" "$new_version"
    update_dependency_version "$chart" "media-servarr-base" "$new_version"

    echo "$chart updated: version to $sub_new_version, base and media-servarr-base dependencies to $new_version"
  done

  echo "Version and dependencies updates completed."
}

main "$@"
