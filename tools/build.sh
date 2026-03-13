#!/bin/bash
set -euo pipefail

cd "${0%/*}"

. ../common.sh no-git

DOTNET_RUNTIME="linux-x64"
if [[ -n "$EXE_SUFFIX" ]]; then
	DOTNET_RUNTIME="win-x64"
fi

# Update
git submodule update --init --recursive --depth 1 --jobs 4

mkdir -p exe

# VRF
cd ValveResourceFormat
#dotnet clean --configuration Release CLI/CLI.csproj
dotnet publish --configuration Release -p:PublishSingleFile=true --self-contained --output ../exe/Source2Viewer/ --runtime "$DOTNET_RUNTIME" -p:DefineConstants=VRF_NO_GENERATOR_VERSION CLI/CLI.csproj

# SteamFileDownloader
cd ../SteamFileDownloader
dotnet publish --configuration Release -p:PublishSingleFile=true --self-contained --output ../exe/SteamFileDownloader/ --runtime "$DOTNET_RUNTIME" SteamFileDownloader.csproj

# ProtobufDumper
cd ../SteamKit
#dotnet clean --configuration Release Resources/ProtobufDumper/ProtobufDumper/ProtobufDumper.csproj
dotnet publish --configuration Release -p:PublishSingleFile=true --self-contained --output ../exe/ProtobufDumper/ --runtime "$DOTNET_RUNTIME" Resources/ProtobufDumper/ProtobufDumper/ProtobufDumper.csproj

# Strings
cd ../DumpStrings
go build -buildvcs=false -o "../exe/DumpStrings${EXE_SUFFIX}"

# Fix Encoding
cd ../FixEncoding
go build -buildvcs=false -o "../exe/FixEncoding${EXE_SUFFIX}"

# Dumper
cd ../DumpSource2
#[[ -d build ]] && rm -r build
mkdir -p build
cmake -B build -S .
cmake --build build --parallel 4 --config Release

# Verify
echo Checking that the executables work
cd ../

"$STEAM_FILE_DOWNLOADER_PATH" --version
"$VRF_PATH" --version
"$PROTOBUF_DUMPER_PATH" -v
"$DUMP_STRINGS_PATH"
"$FIX_ENCODING_PATH"

echo "Done."
