#!/bin/bash

# Debug
# set -e
# set -x

# Get the directory of the script
SCRIPT_DIR=$(realpath $(dirname "$0"))

# Define the build directory
BUILD_DIR="$SCRIPT_DIR/DockerEngineInstaller"
mkdir -p "$BUILD_DIR"

# Define the base_files directory
BASE_DIR="$BUILD_DIR/base_files"
mkdir -p "$BASE_DIR"

# Define the EngineCompose directory
COMPOSE_DIR="$BUILD_DIR/EngineCompose"
mkdir -p "$COMPOSE_DIR"

# URL of the Functions Scripts
DEPENDENCIES_SCRIPT_URL="https://raw.githubusercontent.com/alex-chepurnoy/DockerEngineInstaller/refs/heads/main/install_dependencies.sh"
FETCH_VERSIONS_SCRIPT_URL="https://raw.githubusercontent.com/alex-chepurnoy/DockerEngineInstaller/refs/heads/main/fetch_and_set_wowza_versions.sh"
JKS_FUNCTIONS_SCRIPT_URL="https://raw.githubusercontent.com/alex-chepurnoy/DockerEngineInstaller/refs/heads/main/jks_functions.sh"
TUNING_SCRIPT_URL="https://raw.githubusercontent.com/alex-chepurnoy/DockerEngineInstaller/refs/heads/main/tuning.sh"
CREATE_DOCKER_IMAGE_SCRIPT_URL="https://raw.githubusercontent.com/alex-chepurnoy/DockerEngineInstaller/refs/heads/main/create_docker_image.sh"
PROMPT_CREDENTIALS_SCRIPT_URL="https://raw.githubusercontent.com/alex-chepurnoy/DockerEngineInstaller/refs/heads/main/prompt_credentials.sh"

# Download the Functions Scripts
curl -o "$SCRIPT_DIR/install_dependencies.sh" "$DEPENDENCIES_SCRIPT_URL" > /dev/null 2>&1
curl -o "$SCRIPT_DIR/fetch_and_set_wowza_versions.sh" "$FETCH_VERSIONS_SCRIPT_URL" > /dev/null 2>&1
curl -o "$SCRIPT_DIR/jks_functions.sh" "$JKS_FUNCTIONS_SCRIPT_URL" > /dev/null 2>&1
curl -o "$SCRIPT_DIR/tuning.sh" "$TUNING_SCRIPT_URL" > /dev/null 2>&1
curl -o "$SCRIPT_DIR/create_docker_image.sh" "$CREATE_DOCKER_IMAGE_SCRIPT_URL" > /dev/null 2>&1
curl -o "$SCRIPT_DIR/prompt_credentials.sh" "$PROMPT_CREDENTIALS_SCRIPT_URL" > /dev/null 2>&1

# Source for the Functions Scripts
source "$SCRIPT_DIR/install_dependencies.sh"
source "$SCRIPT_DIR/fetch_and_set_wowza_versions.sh"
source "$SCRIPT_DIR/jks_functions.sh"
source "$SCRIPT_DIR/tuning.sh"
source "$SCRIPT_DIR/create_docker_image.sh"
source "$SCRIPT_DIR/prompt_credentials.sh"

# Check if Docker is installed
echo "   -----Checking if Docker is installed-----"
if ! command -v docker &> /dev/null; then
  install_docker
else
  echo "   -----Docker found-----"
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  install_jq
fi

# Fetch and set Wowza Engine version
engine_version=$(fetch_and_set_wowza_versions)

## Create the Server.xml and VHost.xml files
echo "   -----Creating Server.xml and VHost.xml for SSL file-----"

# Create a temporary container from the image
sudo docker run -d --name temp_container --entrypoint /sbin/entrypoint.sh wowzamedia/wowza-streaming-engine-linux:${engine_version} > /dev/null

# Copy the VHost.xml file from the container to the host
sudo docker cp temp_container:/usr/local/WowzaStreamingEngine/conf/VHost.xml "$BASE_DIR/VHost.xml"
sudo docker cp temp_container:/usr/local/WowzaStreamingEngine/conf/Server.xml "$BASE_DIR/Server.xml"

# Remove the temporary container
sudo docker rm -f temp_container > /dev/null

# Handle JKS file detection and setup
check_for_jks

# Tune the Wowza Streaming Engine configuration
tuning

# Create a Dockerfile and build the Docker image
create_docker_image "$BUILD_DIR" "$BASE_DIR" "$engine_version" "$jks_file"

# Change directory to $COMPOSE_DIR
cd "$COMPOSE_DIR"

# Prompt for credentials and license key
prompt_credentials

# Create docker-compose.yml
cat <<EOL > docker-compose.yml
services:
  wowza:
    image: docker.io/library/wowza_engine:${engine_version}
    container_name: wse_${engine_version}
    restart: always
    ports:
      - "6970-7000:6970-7000/udp"
      - "443:443"
      - "1935:1935"
      - "554:554"
      - "8084-8090:8084-8090/tcp"
    volumes:
      - $BUILD_DIR/DockerWSELogs:/usr/local/WowzaStreamingEngine/logs
      - $BUILD_DIR/DockerWSEcontent:/usr/local/WowzaStreamingEngine/content
    entrypoint: /sbin/entrypoint.sh
    env_file: 
      - ./.env
    environment:
      - WSE_LIC=${WSE_LIC}
      - WSE_MGR_USER=${WSE_MGR_USER}
      - WSE_MGR_PASS=${WSE_MGR_PASS}
EOL

# Run docker compose up
echo "Running docker compose up..."
sudo docker compose up -d

# Wait for the services to start and print logs
echo "Waiting for services to start..."
sleep 3  # Adjust the sleep time as needed

echo "Printing docker compose logs..."
sudo docker compose logs

# Clean up the install directory
echo "Cleaning up the install directory..."

if [ -f "$BASE_DIR/VHost.xml" ]; then
  sudo rm "$BASE_DIR/VHost.xml"
fi

if [ -f "$BASE_DIR/Server.xml" ]; then
  sudo rm "$BASE_DIR/Server.xml"
fi

if [ -f "$BUILD_DIR/Dockerfile" ]; then
  sudo rm "$BUILD_DIR/Dockerfile"
fi

if [ -f "$BASE_DIR/tomcat.properties" ]; then
  sudo rm "$BASE_DIR/tomcat.properties"
fi

# Get the public IP address
public_ip=$(curl -s ifconfig.me)

# Get the private IP address
private_ip=$(ip addr show | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n 1)

# Print instructions to stop WSE and connect to Wowza Streaming Engine Manager
echo "
To stop WSE, type: sudo docker compose -f $COMPOSE_DIR/docker-compose.yml down

"
echo "
Check $BUILD_DIR for Engine Logs and contents directories

"
if [ -n "$jks_domain" ]; then
  echo "To connect to Wowza Streaming Engine Manager over SSL, go to: https://${jks_domain}:8090/enginemanager"
else
  echo "To connect to Wowza Streaming Engine Manager via public IP, go to: http://$public_ip:8088/enginemanager"
  echo "To connect to Wowza Streaming Engine Manager via private IP, go to: http://$private_ip:8088/enginemanager"
fi
