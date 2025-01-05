#!/bin/bash

# Function to clean up the install directory and prompt user to delete Docker images and containers
cleanup() {
  local base_dir=$1
  local build_dir=$2

  echo "Cleaning up the install directory..."

  if [ -f "$base_dir/VHost.xml" ]; then
    sudo rm "$base_dir/VHost.xml"
  fi

  if [ -f "$base_dir/Server.xml" ]; then
    sudo rm "$base_dir/Server.xml"
  fi

  if [ -f "$build_dir/Dockerfile" ]; then
    sudo rm "$build_dir/Dockerfile"
  fi

  if [ -f "$base_dir/tomcat.properties" ]; then
    sudo rm "$base_dir/tomcat.properties"
  fi

  if [ -f "$base_dir/log4j2-config.xml" ]; then
    sudo rm "$base_dir/log4j2-config.xml"
  fi
}