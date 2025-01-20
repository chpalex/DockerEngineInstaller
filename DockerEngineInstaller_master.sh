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
whiptail --title "Docker Engine Workflow Installer" --msgbox "
Welcome to the Docker Engine Workflow Installer!\n\nThis installation script automates the deployment of Wowza Streaming Engine, a simple webserver and SSL in a Docker environment." 20 75

#
## Set directory variables

# Get the directory of the script
SCRIPT_DIR=$(realpath $(dirname "$0"))

# Define the build directory
DockerEngineInstaller="$SCRIPT_DIR/DockerEngineInstaller"
mkdir -p -m 777 "$DockerEngineInstaller"

# Define the base_files directory
upload="$DockerEngineInstaller/upload"
mkdir -p -m 777 "$upload"

# Define the SWAG directory
swag="$DockerEngineInstaller/config"
mkdir -p -m 777 "$swag"

####
## Functions ##

####
# Function to install Docker
install_docker() {
  echo -e "${w}Checking if Docker is installed"
  if ! command -v docker &> /dev/null; then
  echo "   -----Docker not found, starting Docker installation-----"
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo "   -----Docker Installation complete-----"
  else
  echo -e "${w}Docker found"
  fi
}
####
# Function to install jq
install_jq() {
  if ! command -v jq &> /dev/null; then
  echo "   -----jq not found, installing jq-----"
  sudo apt-get install -y jq > /dev/null 2>&1
  fi
}

####
# Fetch and set Wowza versions
fetch_and_set_wowza_versions() {
    local url="https://registry.hub.docker.com/v2/repositories/wowzamedia/wowza-streaming-engine-linux/tags"
    local versions=()
    local max_retries=3
    local retry_count=0

    # Fetch versions with retry logic
    while [ "$url" != "null" ]; do
        response=$(curl -s -f "$url")
        if [ $? -ne 0 ]; then
            retry_count=$((retry_count + 1))
            if [ $retry_count -ge $max_retries ]; then
                echo "Error: Failed to fetch versions after $max_retries attempts"
                exit 1
            fi
            sleep 2
            continue
        fi

        # Process response in a single jq call
        versions+=( $(echo "$response" | jq -r '.results[] | .name') )
        url=$(echo "$response" | jq -r '.next')
    done

    # Early exit if no versions found
    if [ ${#versions[@]} -eq 0 ]; then
        echo "Error: No versions found"
        exit 1
    fi

    # Create menu items directly
    local menu_items=()
    for version in "${versions[@]}"; do
        menu_items+=("$version" "")
    done

    # Calculate menu dimensions
    local menu_height=$(( ${#menu_items[@]} / 2 + 7 ))
    menu_height=$(( menu_height > 20 ? 20 : menu_height ))
    local list_height=$(( ${#menu_items[@]} / 2 ))
    list_height=$(( list_height > 10 ? 10 : list_height ))

    # Select version
    engine_version=$(whiptail --title "Select Wowza Engine Version" \
                             --menu "Available Docker Wowza Engine Versions:" \
                             $menu_height 80 $list_height \
                             "${menu_items[@]}" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ] || [ -z "$engine_version" ]; then
        echo "No Wowza Engine version selected, exiting."
        exit 1
    fi

    # Prompt for Docker container name
    container_name=$(whiptail --inputbox "Enter the name for this WSE install (default: wse_${engine_version}):" \
                              8 78 "wse_${engine_version}" \
                              --title "Docker Container Name" 3>&1 1>&2 2>&3)

    # Check if user canceled or input is empty, set default name
    if [ $? -ne 0 ] || [ -z "$container_name" ]; then
        container_name="wse_${engine_version}"
    fi

    # Create container directory
    container_dir="$DockerEngineInstaller/$container_name"
    mkdir -p "$container_dir" || {
        echo "Error: Failed to create container directory"
        exit 1
    }
}

####
# Function to guide DuckDNS domain setup and SSL creation
duckDNS_create() {
    local readonly DIALOG_WIDTH=60
    local readonly DIALOG_HEIGHT=12
    local DNS_CONF_DIR="$swag/dns-conf"
    local public_ip

    # Get public IP with retry
    for i in {1..3}; do
        public_ip=$(curl -s -f https://api.ipify.org)
        [[ $? -eq 0 && -n "$public_ip" ]] && break
        sleep 2
    done

    [[ -z "$public_ip" ]] && {
        whiptail --title "Error" --msgbox "Failed to get public IP" 8 $DIALOG_WIDTH
        return 1
    }

    # Show instructions
    whiptail --title "DuckDNS Setup" --msgbox "Please: \n\n1. Go to duckdns.org\n2. Create a new domain pointing to: $public_ip\n3. Copy your token\n\nClick OK when ready." $DIALOG_HEIGHT $DIALOG_WIDTH

    # Get domain
    while true; do
        jks_duckdns_domain=$(whiptail --title "DuckDNS Domain" --inputbox "Enter your DuckDNS domain (without .duckdns.org):" 8 $DIALOG_WIDTH 3>&1 1>&2 2>&3)
        
        [[ $? -ne 0 ]] && return 1
        break
    done

    # Get token
    while true; do
        duckdns_token=$(whiptail --title "DuckDNS Token" --inputbox "Enter your DuckDNS token:" 8 $DIALOG_WIDTH 3>&1 1>&2 2>&3)
        
        [[ $? -ne 0 ]] && return 1
        break
    done

    # Export variables and append domain
    export jks_duckdns_domain="${jks_duckdns_domain}.duckdns.org" duckdns_token

    if whiptail --title "DuckDNS Setup" --yesno "Use DuckDNS for Wowza Streaming Engine access?" 10 $DIALOG_WIDTH; then
      # Create JKS file
      touch "$upload/${jks_duckdns_domain}.jks" || {
          whiptail --title "Error" --msgbox "Failed to create JKS file" 8 $DIALOG_WIDTH
          return 1
      }
    else
       check_for_jks
    fi

    return 0
}

####
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
          jks_file="$upload/$jks_file"
          break
        else
          if ! whiptail --title "SSL Configuration" --yesno "You must select a JKS file. Do you want to try again? Use the space button to select." 10 60; then
            whiptail --title "SSL Configuration" --msgbox "No JKS file selected. Exiting." 10 60
            return 1
          fi
        fi
      done

      ssl_config "$jks_file"
    fi
  fi
}

####
# Function to configure SSL
ssl_config() {
  # Extract the base name of the jks_file
  jks_file=$(basename "$1")

  # Check if the jks_file variable contains the word "streamlock"
  if [[ "$jks_file" == *"streamlock"* ]]; then
    jks_domain="${jks_file%.jks}"
  elif [[ "$jks_file" == *"duckdns"* ]]; then
    jks_domain="$jks_duckdns_domain"
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
    jks_password=$(whiptail --title "SSL Configuration" --passwordbox "Please enter a .jks password (if you do not have one, please create one now):" 10 60 3>&1 1>&2 2>&3)
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
}

####
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

####
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
    echo "RUN sed -i '/<\/HostPortList>/i \
    <HostPort>\n\  
        <Name>Autoconfig SSL Streaming</Name>\n\  
        <Type>Streaming</Type>\n\  
        <ProcessorCount>\${com.wowza.wms.TuningAuto}</ProcessorCount>\n\  
        <IpAddress>*</IpAddress>\n\  
        <Port>443</Port>\n\  
        <HTTPIdent2Response></HTTPIdent2Response>\n\  
        <SSLConfig>\n\  
            <KeyStorePath>/usr/local/WowzaStreamingEngine/conf/${jks_file}</KeyStorePath>\n\  
            <KeyStorePassword>${jks_password}</KeyStorePassword>\n\  
            <KeyStoreType>JKS</KeyStoreType>\n\  
            <DomainToKeyStoreMapPath></DomainToKeyStoreMapPath>\n\  
            <SSLProtocol>TLS</SSLProtocol>\n\  
            <Algorithm>SunX509</Algorithm>\n\  
            <CipherSuites></CipherSuites>\n\  
            <Protocols></Protocols>\n\  
            <AllowHttp2>true</AllowHttp2>\n\  
        </SSLConfig>\n\  
        <SocketConfiguration>\n\  
            <ReuseAddress>true</ReuseAddress>\n\  
            <ReceiveBufferSize>0</ReceiveBufferSize>\n\  
            <ReadBufferSize>65000</ReadBufferSize>\n\  
            <SendBufferSize>0</SendBufferSize>\n\  
            <KeepAlive>true</KeepAlive>\n\  
            <AcceptorBackLog>100</AcceptorBackLog>\n\  
        </SocketConfiguration>\n\  
        <HTTPStreamerAdapterIDs>cupertinostreaming,smoothstreaming,sanjosestreaming,dvrchunkstreaming,mpegdashstreaming</HTTPStreamerAdapterIDs>\n\  
        <HTTPProviders>\n\  
            <HTTPProvider>\n\  
                <BaseClass>com.wowza.wms.http.HTTPCrossdomain</BaseClass>\n\  
                <RequestFilters>*crossdomain.xml</RequestFilters>\n\  
                <AuthenticationMethod>none</AuthenticationMethod>\n\  
            </HTTPProvider>\n\  
            <HTTPProvider>\n\  
                <BaseClass>com.wowza.wms.http.HTTPClientAccessPolicy</BaseClass>\n\  
                <RequestFilters>*clientaccesspolicy.xml</RequestFilters>\n\  
                <AuthenticationMethod>none</AuthenticationMethod>\n\  
            </HTTPProvider>\n\  
            <HTTPProvider>\n\  
                <BaseClass>com.wowza.wms.http.HTTPProviderMediaList</BaseClass>\n\  
                <RequestFilters>*jwplayer.rss|*jwplayer.smil|*medialist.smil|*manifest-rtmp.f4m</RequestFilters>\n\  
                <AuthenticationMethod>none</AuthenticationMethod>\n\  
            </HTTPProvider>\n\  
            <HTTPProvider>\n\  
                <BaseClass>com.wowza.wms.webrtc.http.HTTPWebRTCExchangeSessionInfo</BaseClass>\n\  
                <RequestFilters>*webrtc-session.json</RequestFilters>\n\  
                <AuthenticationMethod>none</AuthenticationMethod>\n\  
            </HTTPProvider>\n\  
            <HTTPProvider>\n\  
                <BaseClass>com.wowza.wms.http.HTTPServerVersion</BaseClass>\n\  
                <RequestFilters>*ServerVersion</RequestFilters>\n\  
                <AuthenticationMethod>none</AuthenticationMethod>\n\  
            </HTTPProvider>\n\  
        </HTTPProviders>\n\  
    </HostPort>' /usr/local/WowzaStreamingEngine/conf/VHost.xml" >> Dockerfile

    # Edit the VHost.xml file to include the new TestPlayer block with the jks_domain
    echo "RUN sed -i '/<\/Manager>/i \
    <TestPlayer>\n\
        <IpAddress>${jks_domain}</IpAddress>\n\
        <Port>443</Port>\n\
        <SSLEnable>true</SSLEnable>\n\
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

# Get local timezone
tz=$(timedatectl | grep "Time zone" | awk '{print $3}')

# Create .env file
cat <<EOL > "$container_dir/.env"
WSE_MGR_USER=${WSE_MGR_USER}
WSE_MGR_PASS=${WSE_MGR_PASS}
WSE_LIC=${WSE_LIC}
URL=${jks_domain}
TZ=${tz}
DUCKDNSTOKEN=${duckdns_token}
EOL
}

####
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
  swag:
    image: lscr.io/linuxserver/swag:latest
    container_name: swag
    cap_add:
      - NET_ADMIN
    env_file: 
      - ./.env
    environment:
      - PUID=1000
      - PGID=1000
      - DOCKER_HOST=dockerproxy
      - TZ=\${TZ}
      - URL=\${URL}
      - VALIDATION=dns
      - SUBDOMAINS=www, #optional
      - CERTPROVIDER= #optional
      - DNSPLUGIN=duckdns #optional
      - DUCKDNSTOKEN=${DUCKDNSTOKEN}
      - PROPAGATION= #optional
      - EMAIL= #optional
      - ONLY_SUBDOMAINS=false #optional
      - EXTRA_DOMAINS= #optional
      - STAGING=false #optional
      - DISABLE_F2B= #optional
      - DOCKER_MODS=linuxserver/mods:universal-docker|linuxserver/mods:swag-auto-proxy
    volumes:
      - ${swag}:/config
      - ./www:/config/www
    ports:
      - 444:443
      - 80:80
    labels:
      - swag=enable
    restart: unless-stopped
  dockerproxy:
    image: lscr.io/linuxserver/socket-proxy:latest
    container_name: dockerproxy
    environment:
      - CONTAINERS=1
      - POST=0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
    read_only: true
    tmpfs:
      - /run
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
      - ${swag}/etc/letsencrypt:/usr/local/WowzaStreamingEngine/conf/ssl
      - ./www:/usr/local/WowzaStreamingEngine/www
    entrypoint: /sbin/entrypoint.sh
    env_file: 
      - ./.env
    environment:
      - WSE_LIC=${WSE_LIC}
      - WSE_MGR_USER=${WSE_MGR_USER}
      - WSE_MGR_PASS=${WSE_MGR_PASS}
    labels:
      - swag=enable
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    ports:
      - 9443:9443
    volumes:
      - portainer_data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    labels:
      - swag=enable
    restart: unless-stopped
volumes:
  portainer_data:
    driver: local
  ${volume_name}:
    driver: local
EOL

  # Run docker compose up
  cd "$container_dir"
  sudo docker compose up -d

  # Wait for the services to start and print logs
  echo "Waiting for services to start..."
  sleep 3  # Adjust the sleep time as needed

  echo "Printing docker compose logs..."
  sudo docker compose logs
}

# Function to convert PEM to PKCS12 and then to JKS
convert_pem_to_jks() {
    local domain=$1
    local pem_dir=/usr/local/WowzaStreamingEngine/conf/ssl/archive/$domain
    local jks_dir=/usr/local/WowzaStreamingEngine/conf
    local pkcs12_password=$2
    local jks_password=$3

    # Check if required files are present
    required_files=("cert1.pem" "privkey1.pem" "chain1.pem" "fullchain1.pem")
    timeout=60  # Timeout in seconds
    start_time=$(date +%s)
   
   # Start progress bar
    {
    while true; do
        all_files_present=true
        for file in "${required_files[@]}"; do
            if [ ! -f "$pem_dir/$file" ]; then
                all_files_present=false
                break
            fi
        done

        if $all_files_present; then
            break
        fi

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [ $elapsed_time -ge $timeout ]; then
            echo "Error: Required files not found within the timeout period"
            return 1
        fi
        
            # Update progress bar
            progress=$((elapsed_time * 100 / timeout))
            echo $progress
            sleep 1  # Wait for 1 second before checking again
        done
        # Complete progress bar
        echo 100
     } | whiptail --gauge "Creating $domain.jks file..." 8 60 0
    
    # Convert PEM to PKCS12 and then to JKS inside the Docker container
    docker exec "$container_name" bash -c "
        openssl pkcs12 -export -in '$pem_dir/cert1.pem' -inkey '$pem_dir/privkey1.pem' -out '$jks_dir/$domain.p12' -name '$domain' -passout pass:$pkcs12_password &&
        /usr/local/WowzaStreamingEngine/java/bin/keytool -importkeystore -deststorepass $jks_password -destkeypass $jks_password -destkeystore '$jks_dir/$domain.jks' -srckeystore '$jks_dir/$domain.p12' -srcstoretype PKCS12 -srcstorepass $pkcs12_password -alias '$domain' && 
        /usr/local/WowzaStreamingEngine/java/bin/keytool -import -trustcacerts -alias root -file '$pem_dir/chain1.pem' -keystore '$jks_dir/$domain.jks' -storepass $jks_password -noprompt &&
        /usr/local/WowzaStreamingEngine/java/bin/keytool -import -trustcacerts -alias chain -file '$pem_dir/fullchain1.pem' -keystore '$jks_dir/$domain.jks' -storepass $jks_password -noprompt
    "

    if [ $? -eq 0 ]; then
        echo "Successfully converted PEM to JKS"
    else
        echo "Error: Failed to convert PEM to JKS"
        return 1
    fi

    return 0
}

####
# Function to clean up the install directory and prompt user to delete Docker images and containers
cleanup() {
echo "Cleaning up the install directory..."

  if [ -f "$DockerEngineInstaller/Dockerfile" ]; then
    sudo rm "$DockerEngineInstaller/Dockerfile"
  fi

  if [ -f "$upload/tomcat.properties" ]; then
    sudo rm "$upload/tomcat.properties"
  fi

  if [ -f "$upload/$jks_domain.jks" ]; then
    sudo rm "$upload/$jks_domain.jks"
  fi
}

##### Start the Installation #####
install_docker
install_jq
fetch_and_set_wowza_versions
if [ $? -ne 0 ]; then
  echo -e "${w}Installation cancelled by user."
  exit 1
fi

duckDNS_create
check_for_jks # runs upload_jks, ssl_config
create_docker_image
check_env_prompt_credentials 
create_and_run_docker_compose

# Create symlinks for Engine directories
sudo ln -sf /var/lib/docker/volumes/volume_for_$container_name/_data/conf/ $container_dir/Engine_conf
sudo ln -sf /var/lib/docker/volumes/volume_for_$container_name/_data/logs/ $container_dir/Engine_logs
sudo ln -sf /var/lib/docker/volumes/volume_for_$container_name/_data/content/ $container_dir/Engine_content
sudo ln -sf /var/lib/docker/volumes/volume_for_$container_name/_data/transcoder/ $container_dir/Engine_transcoder
sudo ln -sf /var/lib/docker/volumes/volume_for_$container_name/_data/manager/ $container_dir/Engine_manager
sudo ln -sf /var/lib/docker/volumes/volume_for_$container_name/_data/lib /$container_dir/Engine_lib

convert_pem_to_jks "$jks_domain" "$jks_password" "$jks_password"
cleanup

# Add after symlinks creation
whiptail --title "Engine Directory Management" --msgbox "Volume Mapping Information:
- Engine install directory is mapped to a persistent volume on the host OS
- Volume persists between container reinstalls of the same name
- $container_dir contains links to: conf, logs, transcoder, manager, content, lib

File Management:
1. Edit files directly:
   sudo nano Engine_xxxx/[file_name]

2. Copy files out:
   sudo cp Engine_xxxx/[file_name] [file_name]

3. Copy files back:
   sudo cp [file_name] Engine_xxxx/[file_name]

NOTE: Container must be restarted for changes to take effect:
  cd $container_dir && sudo docker compose stop
  cd $container_dir && sudo docker compose start" 30 100

# Print instructions on how to use the Wowza Streaming Engine Docker container
echo -e "${w}To stop and destroy the Docker Wowza container, type:
${white}cd $container_dir && sudo docker compose down --rmi 'all' && cd $SCRIPT_DIR

${w}To stop the container without destroying it, type:
${white}cd $container_dir && sudo docker compose stop && cd $SCRIPT_DIR

${w}To start the container after stopping it, type:
${white}cd $container_dir && sudo docker compose start && cd $SCRIPT_DIR
"
echo -e "
${w}To access the container directly, type:
${white}sudo docker exec -it $container_name bash
"
echo -e "${w}
* Engine install directory is mapped to a persistent volume on host OS
* Volume persists between container reinstalls of the same name
* $container_dir contains links to: ${NOCOLOR}conf, logs, transcoder, manager, content, lib

${w}File Management:
1. Edit files directly:
   sudo nano Engine_xxxx/[file_name]

2. Copy files out:
   sudo cp Engine_xxxx/[file_name] [file_name]

3. Copy files back:
   sudo cp [file_name] Engine_xxxx/[file_name]

${w}NOTE: Container must be restarted for changes to take effect:
   ${white}cd $container_dir && sudo docker compose stop && sudo docker compose start && cd $SCRIPT_DIR

${w}NOTE: To remove a volume:
   ${white}sudo docker volume rm volume_for_$container_name${NOCOLOR}
"
# Get the public IP address
public_ip=$(curl -s ifconfig.me)

# Get the private IP address
private_ip=$(ip route get 1 | awk '{print $7;exit}')

# Print instructions on how to connect to Wowza Streaming Engine Manager
if [ -n "$jks_domain" ]; then
  echo -e "${yellow}To connect to Wowza Streaming Engine Manager over SSL, go to: ${w}https://${jks_domain}:8090/enginemanager"
else
  echo -e "${yellow}To connect to Wowza Streaming Engine Manager via public IP, go to: ${w}http://$public_ip:8088/enginemanager"
  echo -e "${yellow}To connect to Wowza Streaming Engine Manager via private IP, go to: ${w}http://$private_ip:8088/enginemanager${NOCOLOR}"
fi
if whiptail --title "Cleanup" --yesno "Do you want to delete this installer script?" 8 78; then
  rm $SCRIPT_DIR/DockerEngineInstaller.sh
fi
