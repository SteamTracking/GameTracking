#!/bin/bash
set -euo pipefail

cd "${0%/*}"

# Update
git submodule update --remote --merge --init

# VRF
cd ValveResourceFormat
#dotnet clean --configuration Release CLI/CLI.csproj
dotnet publish --configuration Release -p:PublishSingleFile=true --runtime linux-x64 --self-contained -p:DefineConstants=VRF_NO_GENERATOR_VERSION CLI/CLI.csproj

# ProtobufDumper
cd ../SteamKit
#dotnet clean --configuration Release Resources/ProtobufDumper/ProtobufDumper/ProtobufDumper.csproj
dotnet publish --configuration Release -p:PublishSingleFile=true --runtime linux-x64 --self-contained Resources/ProtobufDumper/ProtobufDumper/ProtobufDumper.csproj

# Strings
cd ../DumpStrings
go build

# Fix Encoding
cd ../FixEncoding
go build

# Dumper
cd ../DumpSource2
git submodule update --init
[[ -d build ]] && rm -r build
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

echo "Done."
