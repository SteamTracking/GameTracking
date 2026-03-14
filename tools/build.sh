#!/bin/bash
set -euo pipefail

cd "${0%/*}"

. ../common.sh no-git

DOTNET_RUNTIME="linux-x64"
if [[ -n "$EXE_SUFFIX" ]]; then
	DOTNET_RUNTIME="win-x64"
fi

# Update
echo "::group::Update submodules"
git submodule update --init --recursive --depth 1 --jobs 4
echo "::endgroup::"

mkdir -p exe

# VRF
echo "::group::Build VRF"
cd ValveResourceFormat
#dotnet clean --configuration Release CLI/CLI.csproj
dotnet publish --configuration Release -p:PublishSingleFile=true --self-contained --output ../exe/Source2Viewer/ --runtime "$DOTNET_RUNTIME" -p:DefineConstants=VRF_NO_GENERATOR_VERSION CLI/CLI.csproj
echo "::endgroup::"

# SteamFileDownloader
echo "::group::Build SteamFileDownloader"
cd ../SteamFileDownloader
dotnet publish --configuration Release -p:PublishSingleFile=true --self-contained --output ../exe/SteamFileDownloader/ --runtime "$DOTNET_RUNTIME" SteamFileDownloader.csproj
echo "::endgroup::"

# ProtobufDumper
echo "::group::Build ProtobufDumper"
cd ../SteamKit
#dotnet clean --configuration Release Resources/ProtobufDumper/ProtobufDumper/ProtobufDumper.csproj
dotnet publish --configuration Release -p:PublishSingleFile=true --self-contained --output ../exe/ProtobufDumper/ --runtime "$DOTNET_RUNTIME" Resources/ProtobufDumper/ProtobufDumper/ProtobufDumper.csproj
echo "::endgroup::"

# Strings
echo "::group::Build DumpStrings"
cd ../DumpStrings
go build -buildvcs=false -o "../exe/DumpStrings${EXE_SUFFIX}"
echo "::endgroup::"

# Fix Encoding
echo "::group::Build FixEncoding"
cd ../FixEncoding
go build -buildvcs=false -o "../exe/FixEncoding${EXE_SUFFIX}"
echo "::endgroup::"

# Dumper
echo "::group::Build DumpSource2"
cd ../DumpSource2
#[[ -d build ]] && rm -r build
mkdir -p build
cmake -B build -S .
cmake --build build --parallel 4 --config Release
echo "::endgroup::"

# Verify
echo "::group::Verify executables"
cd ../

"$STEAM_FILE_DOWNLOADER_PATH" --version
"$VRF_PATH" --version
"$PROTOBUF_DUMPER_PATH" -v
"$DUMP_STRINGS_PATH"
"$FIX_ENCODING_PATH"
echo "::endgroup::"

echo "Done."
