#!/bin/bash

# Function to create Dockerfile and build Docker image for Wowza Engine
create_docker_image() {
  local build_dir=$1
  local base_dir=$2
  local engine_version=$3
  local jks_file=$4

  # Change directory to $BUILD_DIR/
  cd "$build_dir"

  # Create a Dockerfile
  cat <<EOL > Dockerfile
FROM wowzamedia/wowza-streaming-engine-linux:${engine_version}

RUN apt update
RUN apt install nano

WORKDIR /usr/local/WowzaStreamingEngine/
EOL

  # Build the Docker image from specified version
  sudo docker build . -t wowza_engine:$engine_version
}
