#!/bin/bash

# Function to copy files from Engine image for modification
engine_file_fetch() {
  local engine_version=$1
  local base_dir=$2
  local container_dir=$3

  echo "Preparing Wowza Engine files for modification"

  # Create a temporary container from the image
  sudo docker run -d --name temp_container --entrypoint /sbin/entrypoint.sh wowzamedia/wowza-streaming-engine-linux:${engine_version} > /dev/null

  # Copy the VHost.xml file from the container to the host
  sudo docker cp temp_container:/usr/local/WowzaStreamingEngine/conf/ "$container_dir/Engine_conf" > /dev/null 2>&1
  sudo docker cp temp_container:/usr/local/WowzaStreamingEngine/content/sample.mp4 "$container_dir/Engine_content/sample.mp4" > /dev/null 2>&1

  # Remove the temporary container
  sudo docker rm -f temp_container > /dev/null
}
