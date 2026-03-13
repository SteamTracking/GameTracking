#!/bin/bash
set -euo pipefail

cd "${0%/*}"

# Update
git submodule update --init --depth 1 --jobs 4

mkdir -p exe

# VRF
cd ValveResourceFormat
#dotnet clean --configuration Release CLI/CLI.csproj
dotnet publish --configuration Release -p:PublishSingleFile=true --self-contained --output ../exe/Source2Viewer/ --runtime linux-x64 -p:DefineConstants=VRF_NO_GENERATOR_VERSION CLI/CLI.csproj

# SteamFileDownloader
cd ../SteamFileDownloader
dotnet publish --configuration Release -p:PublishSingleFile=true --self-contained --output ../exe/SteamFileDownloader/ --runtime linux-x64 SteamFileDownloader.csproj

# ProtobufDumper
cd ../SteamKit
#dotnet clean --configuration Release Resources/ProtobufDumper/ProtobufDumper/ProtobufDumper.csproj
dotnet publish --configuration Release -p:PublishSingleFile=true --self-contained --output ../exe/ProtobufDumper/ --runtime linux-x64 Resources/ProtobufDumper/ProtobufDumper/ProtobufDumper.csproj

# Strings
cd ../DumpStrings
go build -buildvcs=false -o ../exe/DumpStrings

# Fix Encoding
cd ../FixEncoding
go build -buildvcs=false -o ../exe/FixEncoding

# Dumper
cd ../DumpSource2
git submodule update --init --depth 1 --jobs 4
#[[ -d build ]] && rm -r build
mkdir build
cd build
cmake ..
cmake --build . --parallel 4
cd ../

# Verify
echo Checking that the executables work
cd ../
. ../common.sh

"$VRF_PATH" --version
"$PROTOBUF_DUMPER_PATH" -v
"$DUMP_STRINGS_PATH"
"$STEAM_FILE_DOWNLOADER_PATH" --version

echo "Done."
