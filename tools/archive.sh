#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "Usage: $(basename "$0") <output archive>"
	exit 1
fi

cd "${0%/*}"

. ../common.sh no-git

PATHS=(exe/)

if [[ -n "$EXE_SUFFIX" ]]; then
	PATHS+=(DumpSource2/build/Release/)
else
	PATHS+=(DumpSource2/build/DumpSource2-*)
	PATHS+=(implib/)
fi

tar --create --gzip --file "$1" --exclude='*.pdb' "${PATHS[@]}"
