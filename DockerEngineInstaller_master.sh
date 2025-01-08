#!/bin/bash

# Debug
# set -e
# set -x

#Set colors to Wowza colors
w='\033[38;5;208m'
NOCOLOR='\033[0m'
yellow='\033[38;5;226m'
white='\033[38;5;15m'

# Set message box colors
export NEWT_COLORS='
root=,black'

# Display info box about the script and function scripts
whiptail --title "Docker Engine Installer" --msgbox "This script will:
- Check and install Docker if not present
- Fetch a list of available Docker Wowza Engine versions
- Handle SSL configuration
- Tune Wowza Streaming Engine configuration
- Create a custom Docker image for Wowza Engine
- Prompt for Engine credentials and license key
- Create and run Docker Compose file
- Clean up installation files
- Provide instructions to manage and connect to Wowza Streaming Engine" 20 78

#
## Set directory variables

# Get the directory of the script
SCRIPT_DIR=$(realpath $(dirname "$0"))

# Define the build directory
DockerEngineInstaller="$SCRIPT_DIR/DockerEngineInstaller"
mkdir -p "$DockerEngineInstaller"

# Define the base_files directory
upload="$DockerEngineInstaller/upload"
mkdir -p -m 777 "$upload"

#
## Functions ##

# Function to install Docker
install_docker() {
  echo "   -----Docker not found, starting Docker installation-----"
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo "   -----Docker Installation complete-----"
}

# Function to install jq
install_jq() {
  echo "   -----jq not found, installing jq-----"
  sudo apt-get install -y jq > /dev/null 2>&1
}

# Function to fetch a list of WSE Dockers and prompt to select Wowza Engine version to install
fetch_and_set_wowza_versions() {
  # Fetch all available versions of Wowza Engine from Docker
  all_versions=""
  url="https://registry.hub.docker.com/v2/repositories/wowzamedia/wowza-streaming-engine-linux/tags"
  while [ "$url" != "null" ]; do
    response=$(curl -s "$url")
    tags=$(echo "$response" | jq -r '.results[] | "\(.name) \(.last_updated)"')
    all_versions="$all_versions"$'\n'"$tags"
    url=$(echo "$response" | jq -r '.next')
  done
  
  # Sort versions by date released and remove the date field
  sorted_versions=$(echo "$all_versions" | sort -k2 -r | awk '{print $1}')

  # Convert sorted versions to a format suitable for whiptail
  version_list=()
  while IFS= read -r version; do
    version_list+=("$version" "")
  done <<< "$sorted_versions"

  # Calculate the height of the menu based on the number of versions
  menu_height=$((${#version_list[@]} / 2 + 10))
  [ $menu_height -gt 20 ] && menu_height=20  # Limit the height to 20

  # Calculate the list height
  list_height=$((${#version_list[@]} / 2))
  [ $list_height -gt 10 ] && list_height=10  # Limit the list height to 10

  # Use whiptail to create a menu for selecting the version
  engine_version=$(whiptail --title "Select Wowza Engine Version" --menu "Available Docker Wowza Engine Versions:" $menu_height 80 $list_height "${version_list[@]}" 3>&1 1>&2 2>&3)

  # Prompt for Docker container name
  container_name=$(whiptail --inputbox "Enter the name for this WSE install (default: wse_${engine_version}):" 8 78 "wse_${engine_version}" --title "Docker Container Name" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ] || [ -z "$container_name" ]; then
    container_name="wse_${engine_version}"
  fi

  # Define the Container directory
  container_dir="$DockerEngineInstaller/$container_name"
  mkdir -p "$container_dir"
  engine_conf_dir="$container_dir/Engine_conf"
  mkdir -p -m 777 "$engine_conf_dir"
}

# Function to scan for .jks file
check_for_jks() {
  whiptail --title "SSL Configuration" --msgbox "Starting SSL Configuration\nSearching for existing SSL Java Key Store (JKS) files in $upload" 10 60

  # Find all .jks files
  jks_files=($(ls "$upload"/*.jks 2>/dev/null))
  if [ ${#jks_files[@]} -eq 0 ]; then
    whiptail --title "SSL Configuration" --msgbox "No .jks file/s found." 10 60
    upload_jks
  else
    if [ ${#jks_files[@]} -eq 1 ]; then
      jks_file="${jks_files[0]}"
      if whiptail --title "JKS File/s Detected" --yesno "A .jks file $(basename "$jks_file") was detected. Do you want to use this file?" 10 60; then
        ssl_config "$jks_file"
      else
        upload_jks
      fi
    else
      # Create a radiolist with the list of .jks files
      menu_options=()
      for file in "${jks_files[@]}"; do
        menu_options+=("$(basename "$file")" "" OFF)
      done

      while true; do
        jks_file=$(whiptail --title "SSL Configuration" --radiolist "Multiple JKS files found. Choose one:" 20 60 10 "${menu_options[@]}" 3>&1 1>&2 2>&3)
        
        if [ $? -eq 0 ] && [ -n "$jks_file" ]; then
          break
        else
          if ! whiptail --title "SSL Configuration" --yesno "You must select a JKS file. Do you want to try again? Use the space button to select." 10 60; then
            whiptail --title "SSL Configuration" --msgbox "No JKS file selected. Exiting." 10 60
            return 1
          fi
        fi
      done

      if [ $? -eq 0 ]; then
        ssl_config "$jks_file"
      else
        upload_jks
      fi
    fi
  fi
}

# Function to configure SSL
ssl_config() {

# Extract the base name of the jks_file
jks_file=$(basename "$jks_file")

# Check if the jks_file variable contains the word "streamlock"
if [[ "$jks_file" == *"streamlock"* ]]; then
  jks_domain="${jks_file%.jks}"
else
  jks_domain=""
fi

  # Capture the domain for the .jks file
  while true; do
    jks_domain=$(whiptail --title "SSL Configuration" --inputbox "Provide the domain for .jks file (e.g., myWowzaDomain.com):" 10 60 "$jks_domain" 3>&1 1>&2 2>&3)
    if [ $? -eq 0 ] && [ -n "$jks_domain" ]; then
      break
    else
      if ! whiptail --title "SSL Configuration" --yesno "Domain input is required. Do you want to try again?" 10 60; then
        whiptail --title "SSL Configuration" --msgbox "Domain input cancelled. Continuing without SSL." 10 60
        return 1
      fi
    fi
  done

  # Capture the password for the .jks file
  while true; do
    jks_password=$(whiptail --title "SSL Configuration" --passwordbox "Please enter the .jks password (to establish https connection to Wowza Manager):" 10 60 3>&1 1>&2 2>&3)
    if [ $? -eq 0 ] && [ -n "$jks_password" ]; then
      break
    else
      if ! whiptail --title "SSL Configuration" --yesno "Password input is required. Do you want to try again?" 10 60; then
        whiptail --title "SSL Configuration" --msgbox "Password input cancelled. Continuing without SSL." 10 60
        return 1
      fi
    fi
  done

  # Setup Engine to use SSL for streaming and Manager access #
  # Create the tomcat.properties file

  cat <<EOL > "$upload/tomcat.properties"
httpsPort=8090
httpsKeyStore=/usr/local/WowzaStreamingEngine/conf/${jks_file}
httpsKeyStorePassword=${jks_password}
#httpsKeyAlias=[key-alias]
EOL

  # Copy the .jks file to the Engine conf directory
  if [ -n "$jks_file" ] && [ -f "$upload/$jks_file" ]; then
    cp "$upload/$jks_file" "$engine_conf_dir/$jks_file"
  else
    exit 1
  fi
}

# Function to upload .jks file
upload_jks() {
  while true; do
    if whiptail --title "SSL Configuration" --yesno "Do you want to upload a .jks file?" 10 60; then
      whiptail --title "SSL Configuration" --msgbox "Press [Enter] to continue after uploading the .jks file to $upload..." 10 60

      # Find all .jks files
      jks_files=($(ls "$upload"/*.jks 2>/dev/null))
      if [ ${#jks_files[@]} -eq 0 ]; then
        if whiptail --title "SSL Configuration" --yesno "No .jks file found. Would you like to upload again?" 10 60; then
          continue
        else
          whiptail --title "SSL Configuration" --msgbox "You chose not to add a .jks file. Continuing without SSL." 10 60
          return 1
        fi
      else
        if [ ${#jks_files[@]} -eq 1 ]; then
          jks_file="${jks_files[0]}"
          whiptail --title "SSL Configuration" --msgbox "Found JKS file: $(basename "$jks_file")" 10 60 
        else
          # Create a radiolist with the list of .jks files
          menu_options=()
          for file in "${jks_files[@]}"; do
            menu_options+=("$(basename "$file")" "" OFF)
          done

          while true; do
            jks_file=$(whiptail --title "SSL Configuration" --radiolist "Multiple JKS files found. Choose one:" 20 60 10 "${menu_options[@]}" 3>&1 1>&2 2>&3)
            
            if [ $? -eq 0 ] && [ -n "$jks_file" ]; then
              break
            else
              if ! whiptail --title "SSL Configuration" --yesno "You must select a JKS file. Do you want to try again? Use the space button to select." 10 60; then
                whiptail --title "SSL Configuration" --msgbox "No JKS file selected. Exiting." 10 60
                return 1
              fi
            fi
          done

          if [ $? -ne 0 ]; then
            whiptail --title "SSL Configuration" --msgbox "You chose not to add a .jks file. Continuing without SSL." 10 60
            return 1
          fi
        fi
        ssl_config "$jks_file"
        return 0
      fi
    else
      whiptail --title "SSL Configuration" --msgbox "You chose not to add a .jks file. Continuing without SSL" 10 60
      return 1
    fi
  done
}

# Function to create Dockerfile and build Docker image for Wowza Engine
create_docker_image() {
  # Change directory to $DockerEngineInstaller
  cd "$DockerEngineInstaller"
  
  # Create a Dockerfile
  cat <<EOL > Dockerfile
FROM wowzamedia/wowza-streaming-engine-linux:${engine_version}

RUN apt update && apt install -y nano
WORKDIR /usr/local/WowzaStreamingEngine/

# Create the tuning.sh script
RUN cat <<'EOF' > tuning.sh
#!/bin/bash

# Change ReceiveBufferSize and SendBufferSize values to 0 for <NetConnections> and <MediaCasters>
sed -i "s|<ReceiveBufferSize>.*</ReceiveBufferSize>|<ReceiveBufferSize>0</ReceiveBufferSize>|g" "/usr/local/WowzaStreamingEngine/conf/VHost.xml"
sed -i "s|<SendBufferSize>.*</SendBufferSize>|<SendBufferSize>0</SendBufferSize>|g" "/usr/local/WowzaStreamingEngine/conf/VHost.xml"

# Check CPU thread count
cpu_thread_count=\$(nproc)

# Calculate pool sizes with limits
handler_pool_size=\$((cpu_thread_count * 60))
transport_pool_size=\$((cpu_thread_count * 40))

# Apply limits
if [ "\$handler_pool_size" -gt 4096 ]; then
  handler_pool_size=4096
fi

if [ "\$transport_pool_size" -gt 4096 ]; then
  transport_pool_size=4096
fi

# Update Server.xml with new pool sizes
sed -i "s|<HandlerThreadPool>.*</HandlerThreadPool>|<HandlerThreadPool><PoolSize>\$handler_pool_size</PoolSize></HandlerThreadPool>|" "/usr/local/WowzaStreamingEngine/conf/Server.xml"
sed -i "s|<TransportThreadPool>.*</TransportThreadPool>|<TransportThreadPool><PoolSize>\$transport_pool_size</PoolSize></TransportThreadPool>|" "/usr/local/WowzaStreamingEngine/conf/Server.xml"

# Configure Demo live stream
sed -i "/<\/ServerListeners>/i \
          <ServerListener>\
            <BaseClass>com.wowza.wms.module.ServerListenerStreamDemoPublisher</BaseClass>\
          </ServerListener>" "/usr/local/WowzaStreamingEngine/conf/Server.xml"

# Find the line number of the closing </Properties> tag directly above the closing </Server> tag
line_number=\$(sed -n '/<\/Properties>/=' "/usr/local/WowzaStreamingEngine/conf/Server.xml" | tail -1)

# Insert the new property at the found line number
if [ -n "\$line_number" ]; then
  sed -i "\${line_number}i <Property>\
<Name>streamDemoPublisherConfig</Name>\
<Value>appName=live,srcStream=sample.mp4,dstStream=myStream,sendOnMetadata=true</Value>\
<Type>String</Type>\
</Property>" "/usr/local/WowzaStreamingEngine/conf/Server.xml"
fi

# Edit log4j2-config.xml to comment out serverError appender
sed -i "s|<AppenderRef ref=\"serverError\" level=\"warn\"/>|<!-- <AppenderRef ref=\"serverError\" level=\"warn\"/> -->|g" "/usr/local/WowzaStreamingEngine/conf/log4j2-config.xml"
EOF

RUN chmod +x tuning.sh
RUN ./tuning.sh
RUN rm tuning.sh

EOL

  if [ -f "$upload/tomcat.properties" ]; then
    echo "COPY upload/tomcat.properties /usr/local/WowzaStreamingEngine/manager/conf/" >> Dockerfile
    echo "RUN chown wowza:wowza /usr/local/WowzaStreamingEngine/manager/conf/tomcat.properties" >> Dockerfile

# Change the <Port> line to have only 1935,554 ports
echo "RUN sed -i 's|<Port>1935,80,443,554</Port>|<Port>1935,554</Port>|' /usr/local/WowzaStreamingEngine/conf/VHost.xml" >> Dockerfile

# Edit the VHost.xml file to include the new HostPort block with the JKS and password information
echo "RUN sed -i '/<\/HostPortList>/i \\
  <HostPort>\\
      <Name>Autoconfig SSL Streaming</Name>\\
      <Type>Streaming</Type>\\
      <ProcessorCount>\${com.wowza.wms.TuningAuto}</ProcessorCount>\\
      <IpAddress>*</IpAddress>\\
      <Port>443</Port>\\
      <HTTPIdent2Response></HTTPIdent2Response>\\
      <SSLConfig>\\
          <KeyStorePath>/usr/local/WowzaStreamingEngine/conf/${jks_file}</KeyStorePath>\\
          <KeyStorePassword>${jks_password}</KeyStorePassword>\\
          <KeyStoreType>JKS</KeyStoreType>\\
          <DomainToKeyStoreMapPath></DomainToKeyStoreMapPath>\\
          <SSLProtocol>TLS</SSLProtocol>\\
          <Algorithm>SunX509</Algorithm>\\
          <CipherSuites></CipherSuites>\\
          <Protocols></Protocols>\\
          <AllowHttp2>true</AllowHttp2>\\
      </SSLConfig>\\
      <SocketConfiguration>\\
          <ReuseAddress>true</ReuseAddress>\\
          <ReceiveBufferSize>65000</ReceiveBufferSize>\\
          <ReadBufferSize>65000</ReceiveBufferSize>\\
          <SendBufferSize>65000</SendBufferSize>\\
          <KeepAlive>true</KeepAlive>\\
          <AcceptorBackLog>100</AcceptorBackLog>\\
      </SocketConfiguration>\\
      <HTTPStreamerAdapterIDs>cupertinostreaming,smoothstreaming,sanjosestreaming,dvrchunkstreaming,mpegdashstreaming</HTTPStreamerAdapterIDs>\\
      <HTTPProviders>\\
          <HTTPProvider>\\
              <BaseClass>com.wowza.wms.http.HTTPCrossdomain</BaseClass>\\
              <RequestFilters>*crossdomain.xml</RequestFilters>\\
              <AuthenticationMethod>none</AuthenticationMethod>\\
          </HTTPProvider>\\
          <HTTPProvider>\\
              <BaseClass>com.wowza.wms.http.HTTPClientAccessPolicy</BaseClass>\\
              <RequestFilters>*clientaccesspolicy.xml</RequestFilters>\\
              <AuthenticationMethod>none</AuthenticationMethod>\\
          </HTTPProvider>\\
          <HTTPProvider>\\
              <BaseClass>com.wowza.wms.http.HTTPProviderMediaList</BaseClass>\\
              <RequestFilters>*jwplayer.rss|*jwplayer.smil|*medialist.smil|*manifest-rtmp.f4m</RequestFilters>\\
              <AuthenticationMethod>none</AuthenticationMethod>\\
          </HTTPProvider>\\
          <HTTPProvider>\\
              <BaseClass>com.wowza.wms.webrtc.http.HTTPWebRTCExchangeSessionInfo</BaseClass>\\
              <RequestFilters>*webrtc-session.json</RequestFilters>\\
              <AuthenticationMethod>none</AuthenticationMethod>\\
          </HTTPProvider>\\
          <HTTPProvider>\\
              <BaseClass>com.wowza.wms.http.HTTPServerVersion</BaseClass>\\
              <RequestFilters>*ServerVersion</RequestFilters>\\
              <AuthenticationMethod>none</AuthenticationMethod>\\
          </HTTPProvider>\\
      </HTTPProviders>\\
  </HostPort>' /usr/local/WowzaStreamingEngine/conf/VHost.xml" >> Dockerfile

# Edit the VHost.xml file to include the new TestPlayer block with the jks_domain
echo "RUN sed -i '/<\/Manager>/i \\
  <TestPlayer>\\
      <IpAddress>${jks_domain}</IpAddress>\\
      <Port>443</Port>\\
      <SSLEnable>true</SSLEnable>\\
  </TestPlayer>' /usr/local/WowzaStreamingEngine/conf/VHost.xml" >> Dockerfile

# Edit the Server.xml file to include the JKS and password information
echo "RUN sed -i 's|<Enable>false</Enable>|<Enable>true</Enable>|' /usr/local/WowzaStreamingEngine/conf/Server.xml" >> Dockerfile
echo "RUN sed -i 's|<KeyStorePath></KeyStorePath>|<KeyStorePath>/usr/local/WowzaStreamingEngine/conf/${jks_file}</KeyStorePath>|' /usr/local/WowzaStreamingEngine/conf/Server.xml" >> Dockerfile
echo "RUN sed -i 's|<KeyStorePassword></KeyStorePassword>|<KeyStorePassword>${jks_password}</KeyStorePassword>|' /usr/local/WowzaStreamingEngine/conf/Server.xml" >> Dockerfile
echo "RUN sed -i 's|<IPWhiteList>127.0.0.1</IPWhiteList>|<IPWhiteList>*</IPWhiteList>|' /usr/local/WowzaStreamingEngine/conf/Server.xml" >> Dockerfile
  fi
  
  # Build the Docker image from specified version
  sudo docker build -t wowza_engine:$engine_version .
}

prompt_credentials() {
  # Get user name, password and license key
  WSE_MGR_USER=$(whiptail --inputbox "Provide Wowza username:" 8 78 "$1" --title "Wowza Credentials" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ] || [ -z "$WSE_MGR_USER" ]; then
    whiptail --msgbox "Username is required. Please try again." 8 78 --title "Error"
    WSE_MGR_USER=$(whiptail --inputbox "Provide Wowza username:" 8 78 "$1" --title "Wowza Credentials" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$WSE_MGR_USER" ]; then
      echo "No username provided, exiting install process" >&2
      exit 1
    fi
  fi

  WSE_MGR_PASS=$(whiptail --passwordbox "Provide Wowza password:" 8 78 --title "Wowza Credentials" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ] || [ -z "$WSE_MGR_PASS" ]; then
    whiptail --msgbox "Password is required. Please try again." 8 78 --title "Error"
    WSE_MGR_PASS=$(whiptail --passwordbox "Provide Wowza password:" 8 78 --title "Wowza Credentials" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$WSE_MGR_PASS" ]; then
      echo "No password provided, exiting install process" >&2
      exit 1
    fi
  fi

  WSE_LIC=$(whiptail --inputbox "Provide Wowza license key:" 8 78 "$2" --title "Wowza License Key" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ] || [ -z "$WSE_LIC" ]; then
    whiptail --msgbox "License key is required. Please try again." 8 78 --title "Error"
    WSE_LIC=$(whiptail --inputbox "Provide Wowza license key:" 8 78 "$2" --title "Wowza License Key" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$WSE_LIC" ]; then
      echo "No license key provided, exiting install process" >&2
      exit 1
    fi
  fi
}

check_env_prompt_credentials() {
# Check if .env file exists
if [ -f $container_dir/.env ]; then
  # Read existing values from .env file
  source $container_dir/.env
  # Present a whiptail window with existing data allowing user to make changes
  prompt_credentials "$WSE_MGR_USER" "$WSE_LIC"
else
  # Prompt user for Wowza Streaming Engine Manager credentials and license key using whiptail
  prompt_credentials "" ""
fi

# Create .env file
cat <<EOL > "$container_dir/.env"
WSE_MGR_USER=${WSE_MGR_USER}
WSE_MGR_PASS=${WSE_MGR_PASS}
WSE_LIC=${WSE_LIC}
EOL

}

# Function to create docker-compose.yml and run docker compose up
create_and_run_docker_compose() {
  # Check if the volume exists, create it if it doesn't
  volume_name="volume_for_${container_name}"
  if ! docker volume ls --format '{{.Name}}' | grep -q "^${volume_name}$"; then
    docker volume create "${volume_name}"
  fi

  # Create docker-compose.yml
  cat <<EOL > "$container_dir/docker-compose.yml"
services:
  wowza:
    image: docker.io/library/wowza_engine:${engine_version}
    container_name: ${container_name}
    restart: always
    ports:
      - "6970-7000:6970-7000/udp"
      - "443:443"
      - "1935:1935"
      - "554:554"
      - "8084-8090:8084-8090/tcp"
    volumes:
      - ${volume_name}:/usr/local/WowzaStreamingEngine
    entrypoint: /sbin/entrypoint.sh
    env_file: 
      - ./.env
    environment:
      - WSE_LIC=${wse_lic}
      - WSE_MGR_USER=${wse_mgr_user}
      - WSE_MGR_PASS=${wse_mgr_pass}
volumes:
  ${volume_name}:
    external: true      
EOL

  # Run docker compose up
  echo "Running docker compose up..."
  cd "$container_dir"
  sudo docker compose up -d

  # Wait for the services to start and print logs
  echo "Waiting for services to start..."
  sleep 5  # Adjust the sleep time as needed

  echo "Printing docker compose logs..."
  sudo docker compose logs
}

# Function to clean up the install directory and prompt user to delete Docker images and containers
cleanup() {

  echo "Cleaning up the install directory..."

  if [ -f "$DockerEngineInstaller/Dockerfile" ]; then
    sudo rm "$DockerEngineInstaller/Dockerfile"
  fi

  if [ -f "$upload/tomcat.properties" ]; then
    sudo rm "$upload/tomcat.properties"
  fi
}

# Check if Docker is installed
echo -e "${w}Checking if Docker is installed"
if ! command -v docker &> /dev/null; then
  install_docker
else
  echo -e "${w}Docker found"
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  install_jq
fi

# Define the Container directory
container_dir="$BUILD_DIR/$container_name"
mkdir -p "$container_dir"
engine_conf_dir="$container_dir/Engine_conf"
mkdir -p "$engine_conf_dir"

fetch_and_set_wowza_versions
if [ $? -ne 0 ]; then
  echo -e "${w}Installation cancelled by user."
  exit 1
fi

check_for_jks # runs upload_jks, ssl_config
create_docker_image
check_env_prompt_credentials # runs prompt_credentials
create_and_run_docker_compose
cleanup

# Get the public IP address
public_ip=$(curl -s ifconfig.me)

# Get the private IP address
private_ip=$(ip route get 1 | awk '{print $7;exit}')

# Print instructions on how to use the Wowza Streaming Engine Docker container
echo -e "${w}To stop and destroy the Docker Wowza container, type:
${white}cd $container_dir && sudo docker compose down --rmi 'all' && cd $SCRIPT_DIR${NOCOLOR}

${w}To stop the container without destroying it, type:
${white}cd $container_dir && sudo docker compose stop && cd $SCRIPT_DIR${NOCOLOR}

${w}To start the container after stopping it, type:
${white}cd $container_dir && sudo docker compose start && cd $SCRIPT_DIR${NOCOLOR}

${w}To access the container directly, type:
${white}sudo docker exec -it $container_name bash${NOCOLOR}
"
echo -e "${w}
Check ${white}cd $container_dir${w} for Engine Logs and contents directories
"
if [ -n "$jks_domain" ]; then
  echo -e "${yellow}To connect to Wowza Streaming Engine Manager over SSL, go to: ${w}https://${jks_domain}:8090/enginemanager"
else
  echo -e "${yellow}To connect to Wowza Streaming Engine Manager via public IP, go to: ${w}http://$public_ip:8088/enginemanager"
  echo -e "${yellow}To connect to Wowza Streaming Engine Manager via private IP, go to: ${w}http://$private_ip:8088/enginemanager${NOCOLOR}"
fi

rm $SCRIPT_DIR/DockerEngineInstaller.sh
