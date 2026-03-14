#!/bin/bash

# Use C locale for consistent sorting and string operations
export LC_ALL=C

# Resolve the directory where this script lives
ROOT_DIR="$(dirname "$(realpath -s "${BASH_SOURCE[0]}")")"

# Append .exe suffix on Windows
EXE_SUFFIX=""
if [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
	EXE_SUFFIX=".exe"
fi

# Tool paths
VRF_PATH="$ROOT_DIR/tools/exe/Source2Viewer/Source2Viewer-CLI${EXE_SUFFIX}"
PROTOBUF_DUMPER_PATH="$ROOT_DIR/tools/exe/ProtobufDumper/ProtobufDumper${EXE_SUFFIX}"
DUMP_STRINGS_PATH="$ROOT_DIR/tools/exe/DumpStrings${EXE_SUFFIX}"
STEAM_FILE_DOWNLOADER_PATH="$ROOT_DIR/tools/exe/SteamFileDownloader/SteamFileDownloader${EXE_SUFFIX}"
FIX_ENCODING_PATH="$ROOT_DIR/tools/exe/FixEncoding${EXE_SUFFIX}"

# Allow disabling git operations by passing "no-git" as the first or second argument
DO_GIT=1

if [[ $# -gt 0 ]]; then
	if [[ $1 = "no-git" ]] || [[ $# -gt 1 && $2 = "no-git" ]]; then
		DO_GIT=0
	fi
fi

# ProcessDepot - Processes binary files of a given type by dumping protobufs and extracting strings.
# @param $1 - File extension to process (e.g. .dll, .so, .dylib, .exe)
ProcessDepot ()
{
	echo "::group::Processing binaries ($1)"

#	rm -r "Protobufs"
	mkdir -p "Protobufs"

	# Map the file extension to the binary format type for the strings dumper
	local file_type=""
	case "$1" in
		.dylib)
			file_type="macho"
			;;
		.so)
			file_type="elf"
			;;
		.dll|.exe)
			file_type="pe"
			;;
		*)
			echo "Unknown file type $1"
			echo "::endgroup::"
			return
	esac

	# Find all files matching the given extension and process each one
	while IFS= read -r -d '' file
	do
		# Skip common not game-specific binaries
		if [[ "$(basename "$file" "$1")" = "steamclient" ]] || [[ "$(basename "$file" "$1")" = "libcef" ]]
		then
			continue
		fi

		echo " $file"

		# Extract protobuf definitions from the binary
		"$PROTOBUF_DUMPER_PATH" "$file" "Protobufs/" > /dev/null

		# Derive the output strings filename by replacing the extension with _strings.txt
		if [[ "$1" == ".exe" ]]; then
			strings_file="${file}_strings.txt"
		else
			strings_file="$(echo "$file" | sed -e "s/$(echo "$1" | sed 's/\./\\./g')$/_strings.txt/g")"
		fi

		# Extract readable strings from the binary, sort and deduplicate them
		"$DUMP_STRINGS_PATH" -binary "$file" -target "$file_type" | sort --unique > "$strings_file"
	done <   <(find . -type f -name "*$1" -print0)

	echo "::endgroup::"
}

# ProcessVPK - Lists contents of VPK directory files and writes them to corresponding .txt files.
ProcessVPK ()
{
	echo "::group::Processing VPKs"

	# Find all VPK directory files and dump their file listings to .txt
	while IFS= read -r -d '' file
	do
		echo " $file"

		# Write the VPK's file list to a .txt file with the same name
		"$VRF_PATH" --input "$file" --vpk_list > "$(echo "$file" | sed -e 's/\.vpk$/\.txt/g')"
	done <   <(find . -type f -name "*_dir.vpk" -print0)

	echo "::endgroup::"
}

# DeduplicateStringsFrom - Removes duplicate string lines from extracted strings files
#   by filtering out lines that appear in the provided dedupe reference files.
# @param $1 - File suffix to match binaries (e.g. .dll, .so)
# @param $@ - One or more reference files whose lines will be subtracted from other strings files
DeduplicateStringsFrom ()
{
	suffix="$1"
	shift

	echo "::group::Deduplicating strings ($suffix)"

	# Resolve all dedupe reference files to absolute paths, warn if missing
	dedupe_files=()
	for file in "$@"; do
		resolved="$(realpath "$file")"
		if [[ -f "$resolved" ]]; then
			dedupe_files+=("$resolved")
		else
			echo "::warning::Dedupe file not found: $file"
		fi
	done

	# Merge all reference files into a single sorted set
	merged_dedupe="$(mktemp)"
	sort --unique --merge "${dedupe_files[@]}" > "$merged_dedupe"

	# Iterate over all binaries matching the suffix and process their strings files
	while IFS= read -r -d '' file
	do
		# Derive the corresponding _strings.txt path from the binary path
		target_file="$(realpath "$file" | sed -e "s/$(echo "$suffix" | sed 's/\./\\./g')$/_strings.txt/g")"

		# Skip if no strings file exists for this binary
		if ! [[ -f "$target_file" ]]; then
			continue
		fi

		# Don't deduplicate a file against itself
		for dedupe_file in "${dedupe_files[@]}"; do
			if [[ "$dedupe_file" = "$target_file" ]]; then
				continue 2
			fi
		done

		# Remove lines present in reference files and replace the original
		comm -23 "$target_file" "$merged_dedupe" > "$target_file.tmp"
		mv "$target_file.tmp" "$target_file"
	done <   <(find . -type f -name "*$suffix" -print0)

	rm -f "$merged_dedupe"

	echo "::endgroup::"
}

# ProcessToolAssetInfo - Converts binary tools asset info files (*asset_info.bin) to readable .txt format.
ProcessToolAssetInfo ()
{
	echo "::group::Processing tools asset info"

	# Find all tools asset info binaries and convert them to text
	while IFS= read -r -d '' file
	do
		echo " $file"

		# Dump asset info in short format, replacing .bin extension with .txt
		"$VRF_PATH" --input "$file" --output "$(echo "$file" | sed -e 's/\.bin$/\.txt/g')" --tools_asset_info_short || echo "S2V failed to dump tools asset info"
	done <   <(find . -type f -name "*asset_info.bin" -print0)

	echo "::endgroup::"
}

# FixUCS2 - Converts UCS-2 encoded .txt files to UTF-8 using the FixEncoding tool.
FixUCS2 ()
{
	echo "::group::Fixing encodings"

	# Run FixEncoding on all .txt files in parallel (up to 3 at a time)
	find . -type f -name "*.txt" -print0 | xargs --null --max-lines=1 --max-procs=3 "$FIX_ENCODING_PATH"

	echo "::endgroup::"
}

# CreateCommit - Stages all changes, creates a git commit with a summary message, and pushes.
# @param $1 - Commit message prefix (e.g. game/app name)
# @param $2 - (optional) Patch notes ID appended as a SteamDB URL in the commit body
CreateCommit ()
{
	# Skip if git operations were disabled via "no-git" argument
	if ! [[ $DO_GIT == 1 ]]; then
		echo "Not performing git commit"
		return
	fi

	echo "::group::Creating commit"

	# Stage all changes including untracked files
	git add --all

	# Build commit message: "<prefix> | <file count> files | <comma-separated change list truncated to 1024 chars>"
	message="$1 | $(git diff --cached --numstat | wc -l) files | $(git diff --cached --name-status | sed '{:q;N;s/\n/, /g;t q}' | cut -c 1-1024)"

	# Append a SteamDB patchnotes link if a patch notes ID was provided
	if [[ -n "$2" ]]; then
		bashpls=$'\n\n'
		message="${message}${bashpls}https://steamdb.info/patchnotes/$2/"
	fi

	# Commit (allow failure if there are no changes) and push
	git commit --message "$message" || true
	git push

	echo "::endgroup::"
}
