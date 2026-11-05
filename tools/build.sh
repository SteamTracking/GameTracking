#!/bin/bash
set -euo pipefail

# Usage: build.sh [target...] [--skip target...]
# Targets: submodules vrf steamfiledownloader protobufdumper dumpstrings dumpsource2 verify
# Without targets, all of them are run in that order, except the ones passed to --skip.

cd "${0%/*}"

. ../common.sh no-git

TOOLS_DIR="$PWD"

DOTNET_RUNTIME="linux-x64"
if [[ -n "$EXE_SUFFIX" ]]; then
	DOTNET_RUNTIME="win-x64"
fi

UpdateSubmodules ()
{
	echo "::group::Update submodules"
	cd "$TOOLS_DIR"
	git submodule update --init --recursive --depth 1 --jobs 4
	echo "::endgroup::"
}

BuildVRF ()
{
	echo "::group::Build VRF"
	cd "$TOOLS_DIR/ValveResourceFormat"
	#dotnet clean --configuration Release CLI/CLI.csproj
	dotnet publish --configuration Release -p:PublishSingleFile=true -p:PublishReadyToRun=true --self-contained --output ../exe/Source2Viewer/ --runtime "$DOTNET_RUNTIME" -p:DefineConstants=VRF_NO_GENERATOR_VERSION -p:RunAnalyzers=false CLI/CLI.csproj
	echo "::endgroup::"
}

BuildSteamFileDownloader ()
{
	echo "::group::Build SteamFileDownloader"
	cd "$TOOLS_DIR/SteamFileDownloader"
	dotnet publish --configuration Release -p:PublishSingleFile=true -p:PublishReadyToRun=true --self-contained --output ../exe/SteamFileDownloader/ --runtime "$DOTNET_RUNTIME" -p:RunAnalyzers=false SteamFileDownloader.csproj
	echo "::endgroup::"
}

BuildProtobufDumper ()
{
	echo "::group::Build ProtobufDumper"
	cd "$TOOLS_DIR/SteamKit"
	#dotnet clean --configuration Release Resources/ProtobufDumper/ProtobufDumper/ProtobufDumper.csproj
	dotnet publish --configuration Release -p:PublishSingleFile=true -p:PublishReadyToRun=true --self-contained --output ../exe/ProtobufDumper/ --runtime "$DOTNET_RUNTIME" -p:RunAnalyzers=false Resources/ProtobufDumper/ProtobufDumper/ProtobufDumper.csproj
	echo "::endgroup::"
}

BuildDumpStrings ()
{
	echo "::group::Build DumpStrings"
	cd "$TOOLS_DIR/DumpStrings"
	go build -buildvcs=false -o "../exe/DumpStrings${EXE_SUFFIX}"
	echo "::endgroup::"
}

BuildDumpSource2 ()
{
	echo "::group::Build DumpSource2"
	cd "$TOOLS_DIR/DumpSource2"
	#[[ -d build ]] && rm -r build
	mkdir -p build
	cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
	cmake --build build --parallel 4 --config Release
	echo "::endgroup::"
}

VerifyExecutables ()
{
	echo "::group::Verify executables"
	cd "$TOOLS_DIR"
	"$STEAM_FILE_DOWNLOADER_PATH" --version
	"$VRF_PATH" --version
	"$PROTOBUF_DUMPER_PATH" -v
	"$DUMP_STRINGS_PATH" version
	echo "::endgroup::"
}

TARGETS=()
SKIPPED=()

while [[ $# -gt 0 ]]; do
	if [[ "$1" == "--skip" ]]; then
		SKIPPED+=("$2")
		shift 2
	else
		TARGETS+=("$1")
		shift
	fi
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
	TARGETS=(submodules vrf steamfiledownloader protobufdumper dumpstrings dumpsource2 verify)
fi

mkdir -p exe

for target in "${TARGETS[@]}"; do
	if [[ " ${SKIPPED[*]} " == *" $target "* ]]; then
		continue
	fi

	case "$target" in
		submodules) UpdateSubmodules ;;
		vrf) BuildVRF ;;
		steamfiledownloader) BuildSteamFileDownloader ;;
		protobufdumper) BuildProtobufDumper ;;
		dumpstrings) BuildDumpStrings ;;
		dumpsource2) BuildDumpSource2 ;;
		verify) VerifyExecutables ;;
		*)
			echo "Unknown target: $target"
			exit 1
			;;
	esac
done

echo "Done."
