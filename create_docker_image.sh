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

  # Append COPY commands if the files exist
  if [ -n "$jks_file" ] && [ -f "$base_dir/$jks_file" ]; then
    echo "COPY base_files/${jks_file} /usr/local/WowzaStreamingEngine/conf/" >> Dockerfile
    echo "RUN chown wowza:wowza /usr/local/WowzaStreamingEngine/conf/${jks_file}" >> Dockerfile
  fi

  # Build the Docker image from specified version
  sudo docker build . -t wowza_engine:$engine_version
}
