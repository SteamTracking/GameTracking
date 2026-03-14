#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "$(basename "$0") <mod name>"
	exit 1
fi

TOOLS_DIR="$(dirname "$(realpath -s "${BASH_SOURCE[0]}")")"

echo "::group::DumpSource2-$1"

mkdir -p "DumpSource2"

if [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
	DUMPER_PATH="$TOOLS_DIR/DumpSource2/build/Release/DumpSource2-$1.exe"
	DUMP_DIR="$(realpath "DumpSource2/")"

	cd "$(realpath "game/bin/win64/")" || exit 1

	set +e
	timeout 2m "$DUMPER_PATH" "$DUMP_DIR"
	DUMPER_EXIT_CODE=$?
	set -e
else
	DUMPER_PATH="$TOOLS_DIR/DumpSource2/build/DumpSource2-$1"

	CORE_DIR="$(realpath "game/bin/linuxsteamrt64/")"
	DUMP_DIR="$(realpath "DumpSource2/")"

	cd "$CORE_DIR" || exit 1

	# Create a stub of libvideo to avoid installing video dependencies
	python3 "$TOOLS_DIR/implib/implib-gen.py" --no-dlopen libvideo.so
	mv libvideo.so libvideo.so.original
	gcc -DIMPLIB_EXPORT_SHIMS=1 -g -fPIC -shared libvideo.so.tramp.S libvideo.so.init.c -ldl -o libvideo.so
	rm libvideo.so.tramp.S libvideo.so.init.c

	set +e
	LD_LIBRARY_PATH="$CORE_DIR" timeout 2m "$DUMPER_PATH" "$DUMP_DIR"
	DUMPER_EXIT_CODE=$?
	set -e

	mv libvideo.so.original libvideo.so
fi

# Deduplicate .stringsignore
STRINGSIGNORE="$DUMP_DIR/.stringsignore"
if [[ -f "$STRINGSIGNORE" ]]; then
	sort -u "$STRINGSIGNORE" > "$STRINGSIGNORE.tmp" && mv "$STRINGSIGNORE.tmp" "$STRINGSIGNORE"
fi

if [[ $DUMPER_EXIT_CODE -ne 0 ]]; then
	echo "::error title=DumpSource2-$1 failed::Exit code $DUMPER_EXIT_CODE"
fi

echo "::endgroup::"

exit "$DUMPER_EXIT_CODE"
