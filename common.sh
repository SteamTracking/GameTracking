#!/bin/bash

export LC_ALL=C

ROOT_DIR="$(dirname "$(realpath -s "${BASH_SOURCE[0]}")")"

EXE_SUFFIX=""
if [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
	EXE_SUFFIX=".exe"
fi

VRF_PATH="$ROOT_DIR/tools/exe/Source2Viewer/Source2Viewer-CLI${EXE_SUFFIX}"
PROTOBUF_DUMPER_PATH="$ROOT_DIR/tools/exe/ProtobufDumper/ProtobufDumper${EXE_SUFFIX}"
DUMP_STRINGS_PATH="$ROOT_DIR/tools/exe/DumpStrings${EXE_SUFFIX}"
STEAM_FILE_DOWNLOADER_PATH="$ROOT_DIR/tools/exe/SteamFileDownloader/SteamFileDownloader${EXE_SUFFIX}"
FIX_ENCODING_PATH="$ROOT_DIR/tools/exe/FixEncoding${EXE_SUFFIX}"
DO_GIT=1

if [[ $# -gt 0 ]]; then
	if [[ $1 = "no-git" ]] || [[ $# -gt 1 && $2 = "no-git" ]]; then
		DO_GIT=0
	fi
fi

ProcessDepot ()
{
	echo "> Processing binaries"

#	rm -r "Protobufs"
	mkdir -p "Protobufs"

	while IFS= read -r -d '' file
	do
		if [[ "$(basename "$file" "$1")" = "steamclient" ]] || [[ "$(basename "$file" "$1")" = "libcef" ]]
		then
			continue
		fi

		echo " > $file"

		# Dump protobufs
		"$PROTOBUF_DUMPER_PATH" "$file" "Protobufs/" > /dev/null

		# Dump strings
		file_type=""
		case "$1" in
			.dylib)
				file_type="macho"
				;;
			.so)
				file_type="elf"
				;;
			.dll)
				file_type="pe"
				;;
			.exe)
				file_type="pe"
				;;
			*)
				echo "Unknown file type $1"
				continue
		esac

		if [[ "$1" == ".exe" ]]; then
			strings_file="${file}_strings.txt"
		else
			strings_file="$(echo "$file" | sed -e "s/$(echo "$1" | sed 's/\./\\./g')$/_strings.txt/g")"
		fi

		"$DUMP_STRINGS_PATH" -binary "$file" -target "$file_type" | sort --unique > "$strings_file"
	done <   <(find . -type f -name "*$1" -print0)
}

ProcessVPK ()
{
	echo "> Processing VPKs"

	while IFS= read -r -d '' file
	do
		echo " > $file"

		"$VRF_PATH" --input "$file" --vpk_list > "$(echo "$file" | sed -e 's/\.vpk$/\.txt/g')"
	done <   <(find . -type f -name "*_dir.vpk" -print0)
}

DeduplicateStringsFrom ()
{
	suffix="$1"
	shift

	echo "> Deduplicating strings ($suffix)"

	dedupe_files=()
	for file in "$@"; do
		dedupe_files+=("$(realpath "$file")")
	done

	grep_args=(
		--fixed-strings
		--line-regexp
		--invert-match
	)

	for dedupe_file in "${dedupe_files[@]}"; do
		grep_args+=(--file "$dedupe_file")
	done

	while IFS= read -r -d '' file
	do
		target_file="$(realpath "$file" | sed -e "s/$(echo "$suffix" | sed 's/\./\\./g')$/_strings.txt/g")"

		if ! [[ -f "$target_file" ]]; then
			continue
		fi

		for dedupe_file in "${dedupe_files[@]}"; do
			if [[ "$dedupe_file" = "$target_file" ]]; then
				continue 2
			fi
		done

		grep "${grep_args[@]}" "$target_file" > "$target_file.tmp" || true
		mv "$target_file.tmp" "$target_file"
	done <   <(find . -type f -name "*$suffix" -print0)
}

ProcessToolAssetInfo ()
{
	echo "> Processing tools asset info"

	while IFS= read -r -d '' file
	do
		echo " > $file"

		"$VRF_PATH" --input "$file" --output "$(echo "$file" | sed -e 's/\.bin$/\.txt/g')" --tools_asset_info_short || echo "S2V failed to dump tools asset info"
	done <   <(find . -type f -name "*asset_info.bin" -print0)
}

FixUCS2 ()
{
	echo "> Fixing UCS-2"

	find . -type f -name "*.txt" -print0 | xargs --null --max-lines=1 --max-procs=3 "$FIX_ENCODING_PATH"
}

CreateCommit ()
{
	if ! [[ $DO_GIT == 1 ]]; then
		echo "Not performing git commit"
		return
	fi

	git add --renormalize --all

	message="$1 | $(git diff --cached --numstat | wc -l) files | $(git diff --cached --name-status | sed '{:q;N;s/\n/, /g;t q}' | cut -c 1-1024)"

	if [[ -n "$2" ]]; then
		bashpls=$'\n\n'
		message="${message}${bashpls}https://steamdb.info/patchnotes/$2/"
	fi

	git commit --message "$message" || true
	git push
}
