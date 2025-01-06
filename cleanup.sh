#!/bin/bash

# Function to clean up the install directory and prompt user to delete Docker images and containers
cleanup() {
  local base_dir=$1
  local build_dir=$2
  local SCRIPT_DIR=$3

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

  #Remove downloaded script files
  if [  -f "$SCRIPT_DIR/tuning.sh" ]; then
  sudo rm "$SCRIPT_DIR/tuning.sh"
  fi

  if [  -f "$SCRIPT_DIR/install_dependencies.sh" ]; then 
  sudo rm "$SCRIPT_DIR/install_dependencies.sh"
  fi

  if [  -f "$SCRIPT_DIR/fetch_and_set_wowza_versions.sh" ]; then
  sudo rm "$SCRIPT_DIR/fetch_and_set_wowza_versions.sh"
  fi

  if [  -f "$SCRIPT_DIR/jks_functions.sh" ]; then
  sudo rm "$SCRIPT_DIR/jks_functions.sh"
  fi

  if [  -f "$SCRIPT_DIR/create_docker_image.sh" ]; then
  sudo rm "$SCRIPT_DIR/create_docker_image.sh"
  fi

  if [  -f "$SCRIPT_DIR/prompt_credentials.sh" ]; then
  sudo rm "$SCRIPT_DIR/prompt_credentials.sh"
  fi

  if [  -f "$SCRIPT_DIR/create_and_run_docker_compose.sh" ]; then
  sudo rm "$SCRIPT_DIR/create_and_run_docker_compose.sh"
  fi

  if [  -f "$SCRIPT_DIR/engine_file_fetch.sh" ]; then
  sudo rm "$SCRIPT_DIR/engine_file_fetch.sh"
  fi

  rm -- "$0"
}
