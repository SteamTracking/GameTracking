#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
	echo "$(basename "$0") <game folder name> <mod name>"
	exit 1
fi

TOOLS_DIR="$(dirname "$(realpath -s "${BASH_SOURCE[0]}")")"

if [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
	DUMPER_PATH="$TOOLS_DIR/DumpSource2/build/Release/DumpSource2-$2.exe"
	DUMP_DIR="$(realpath "../$1/DumpSource2/")"

	cd "$(realpath "../$1/game/bin/win64/")" || exit 1

	set +e
	timeout 2m "$DUMPER_PATH" "$DUMP_DIR"
	exit $?
else
	DUMPER_PATH="$TOOLS_DIR/DumpSource2/build/DumpSource2-$2"

	cd "$TOOLS_DIR" || exit 1

	CORE_DIR="$(realpath "../$1/game/bin/linuxsteamrt64/")"
	DUMP_DIR="$(realpath "../$1/DumpSource2/")"

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

	exit "$DUMPER_EXIT_CODE"
fi
