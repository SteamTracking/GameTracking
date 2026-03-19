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

# _ProcessBinary - Processes a single binary file by dumping protobufs and extracting strings.
# @param $1 - File path to process
# @param $2 - File extension (e.g. .dll, .so, .dylib, .exe)
_ProcessBinary ()
{
	local file="$1"
	local ext="$2"

	# Skip common not game-specific binaries
	if [[ "$(basename "$file" "$ext")" = "steamclient" ]] || [[ "$(basename "$file" "$ext")" = "libcef" ]]
	then
		return
	fi

	echo " $file"

	# Extract protobuf definitions from the binary
	"$PROTOBUF_DUMPER_PATH" "$file" "Protobufs/" > /dev/null

	# Derive the output strings filename by replacing the extension with _strings.txt
	local strings_file
	if [[ "$ext" == ".exe" ]]; then
		strings_file="${file}_strings.txt"
	else
		strings_file="${file/%$ext/_strings.txt}"
	fi

	# Extract readable strings from the binary, sort and deduplicate them
	"$DUMP_STRINGS_PATH" -binary "$file" | sort --unique > "$strings_file"
}

# ProcessDepot - Processes binary files by dumping protobufs and extracting strings.
# @param $@ - File extensions to process (e.g. .dll .so .dylib .exe)
ProcessDepot ()
{
	echo "::group::Processing binaries ($*)"

#	rm -r "Protobufs"
	mkdir -p "Protobufs"

	local max_jobs=10
	local job_count=0

	for ext in "$@"; do
		# Find all files matching the given extension and process each one
		while IFS= read -r -d '' file
		do
			_ProcessBinary "$file" "$ext" &

			((job_count++))
			if ((job_count >= max_jobs)); then
				wait -n
				((job_count--))
			fi
		done <   <(find . -type f -name "*$ext" -print0)
	done

	wait

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
		"$VRF_PATH" --input "$file" --vpk_list > "${file/%.vpk/.txt}"
	done <   <(find . -type f -name "*_dir.vpk" -print0)

	echo "::endgroup::"
}

# _DeduplicateStringsFile - Deduplicates a single strings file against a merged reference.
# @param $1 - Strings file to deduplicate
# @param $2 - Merged dedupe reference file
_DeduplicateStringsFile ()
{
	local target_file="$1"
	local merged_dedupe="$2"

	# Remove lines present in reference files and replace the original
	comm -23 "$target_file" "$merged_dedupe" > "$target_file.tmp"
	mv "$target_file.tmp" "$target_file"
}

# DeduplicateStringsFrom - Removes duplicate string lines from extracted strings files
#   by filtering out lines that appear in the provided dedupe reference files.
# @param -- - Separator between suffixes and reference files
# @usage DeduplicateStringsFrom .dll .exe -- file1.txt file2.txt
DeduplicateStringsFrom ()
{
	# Split arguments into suffixes (before --) and reference files (after --)
	local suffixes=()
	local ref_files=()
	local found_separator=0

	for arg in "$@"; do
		if [[ "$arg" == "--" ]]; then
			found_separator=1
		elif ((found_separator)); then
			ref_files+=("$arg")
		else
			suffixes+=("$arg")
		fi
	done

	echo "::group::Deduplicating strings (${suffixes[*]})"

	# Resolve all dedupe reference files to absolute paths, warn if missing
	local dedupe_files=()
	for file in "${ref_files[@]}"; do
		local resolved
		resolved="$(realpath "$file")"
		if [[ -f "$resolved" ]]; then
			dedupe_files+=("$resolved")
		else
			echo "::warning::Dedupe file not found: $file"
		fi
	done

	# Merge all reference files into a single sorted set
	local merged_dedupe
	merged_dedupe="$(mktemp)"
	sort --unique --merge "${dedupe_files[@]}" > "$merged_dedupe"

	local max_jobs=10
	local job_count=0

	for suffix in "${suffixes[@]}"; do
		# Iterate over all binaries matching the suffix and process their strings files
		while IFS= read -r -d '' file
		do
			# Derive the corresponding _strings.txt path from the binary path
			local resolved_file
			resolved_file="$(realpath "$file")"
			local target_file
			if [[ "$suffix" == ".exe" ]]; then
				target_file="${resolved_file}_strings.txt"
			else
				target_file="${resolved_file/%$suffix/_strings.txt}"
			fi

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

			_DeduplicateStringsFile "$target_file" "$merged_dedupe" &

			((job_count++))
			if ((job_count >= max_jobs)); then
				wait -n
				((job_count--))
			fi
		done <   <(find . -type f -name "*$suffix" -print0)
	done

	wait

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
		"$VRF_PATH" --input "$file" --output "${file/%.bin/.txt}" --tools_asset_info_short || echo "S2V failed to dump tools asset info"
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
