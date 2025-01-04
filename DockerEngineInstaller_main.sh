#!/bin/bash

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

# Download the Functions Scripts
curl -o "$SCRIPT_DIR/install_dependencies.sh" "$DEPENDENCIES_SCRIPT_URL" > /dev/null 2>&1
curl -o "$SCRIPT_DIR/fetch_and_set_wowza_versions.sh" "$FETCH_VERSIONS_SCRIPT_URL" > /dev/null 2>&1
curl -o "$SCRIPT_DIR/jks_functions.sh" "$JKS_FUNCTIONS_SCRIPT_URL" > /dev/null 2>&1
curl -o "$SCRIPT_DIR/tuning.sh" "$TUNING_SCRIPT_URL" > /dev/null 2>&1
 
# Source for the Functions Scripts
source "$SCRIPT_DIR/install_dependencies.sh"
source "$SCRIPT_DIR/fetch_and_set_wowza_versions.sh"
source "$SCRIPT_DIR/jks_functions.sh"
source "$SCRIPT_DIR/tuning.sh"

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

tuning "$BUILD_DIR"

# Change directory to $BUILD_DIR/
cd "$BUILD_DIR"

# Create a Dockerfile
cat <<EOL > Dockerfile
FROM wowzamedia/wowza-streaming-engine-linux:${engine_version}

RUN apt update
RUN apt install nano

WORKDIR /usr/local/WowzaStreamingEngine/
EOL

# Append COPY commands if the files exist
if [ -n "$jks_file" ] && [ -f "$BASE_DIR/$jks_file" ]; then
  echo "COPY base_files/${jks_file} /usr/local/WowzaStreamingEngine/conf/" >> Dockerfile
  echo "RUN chown wowza:wowza /usr/local/WowzaStreamingEngine/conf/${jks_file}" >> Dockerfile
fi

if [ -f "$BASE_DIR/tomcat.properties" ]; then
  echo "COPY base_files/tomcat.properties /usr/local/WowzaStreamingEngine/manager/conf/" >> Dockerfile
  echo "RUN chown wowza:wowza /usr/local/WowzaStreamingEngine/manager/conf/tomcat.properties" >> Dockerfile
fi

if [ -f "$BASE_DIR/Server.xml" ]; then
  echo "COPY base_files/Server.xml /usr/local/WowzaStreamingEngine/conf/" >> Dockerfile
  echo "RUN chown wowza:wowza /usr/local/WowzaStreamingEngine/conf/Server.xml" >> Dockerfile
fi

if [ -f "$BASE_DIR/VHost.xml" ]; then
  echo "COPY base_files/VHost.xml /usr/local/WowzaStreamingEngine/conf/" >> Dockerfile
  echo "RUN chown wowza:wowza /usr/local/WowzaStreamingEngine/conf/VHost.xml" >> Dockerfile
fi

# Build the Docker image from specified version
sudo docker build . -t wowza_engine:$engine_version

# Change directory to $COMPOSE_DIR
cd "$COMPOSE_DIR"

# Prompt user for Wowza Streaming Engine Manager credentials and license key
read -p "Provide Wowza username: " WSE_MGR_USER
read -s -p "Provide Wowza password: " WSE_MGR_PASS
echo
read -p "Provide Wowza license key: " WSE_LIC
echo

# Create .env file
cat <<EOL > .env
WSE_MGR_USER=${WSE_MGR_USER}
WSE_MGR_PASS=${WSE_MGR_PASS}
WSE_LIC=${WSE_LIC}
EOL

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

# Clean up the install directory
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
