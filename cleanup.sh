#!/bin/bash

# Function to clean up the install directory and prompt user to delete Docker images and containers
cleanup() {
  local base_dir=$1
  local script_dir=$2

  echo "Cleaning up the install directory..."

  if [ -f "$base_dir/Dockerfile" ]; then
    sudo rm "$base_dir/Dockerfile"
  fi

  #Remove downloaded script files
  if [  -f "$script_dir/tuning.sh" ]; then
  sudo rm "$script_dir/tuning.sh"
  fi

  if [  -f "$script_dir/install_dependencies.sh" ]; then 
  sudo rm "$script_dir/install_dependencies.sh"
  fi

  if [  -f "$script_dir/fetch_and_set_wowza_versions.sh" ]; then
  sudo rm "$script_dir/fetch_and_set_wowza_versions.sh"
  fi

  if [  -f "$script_dir/jks_functions.sh" ]; then
  sudo rm "$script_dir/jks_functions.sh"
  fi

  if [  -f "$script_dir/create_docker_image.sh" ]; then
  sudo rm "$script_dir/create_docker_image.sh"
  fi

  if [  -f "$script_dir/prompt_credentials.sh" ]; then
  sudo rm "$script_dir/prompt_credentials.sh"
  fi

  if [  -f "$script_dir/create_and_run_docker_compose.sh" ]; then
  sudo rm "$script_dir/create_and_run_docker_compose.sh"
  fi

  if [  -f "$script_dir/engine_file_fetch.sh" ]; then
  sudo rm "$script_dir/engine_file_fetch.sh"
  fi

  rm "$script_dir/cleanup.sh"
}

rm -- "$0"

