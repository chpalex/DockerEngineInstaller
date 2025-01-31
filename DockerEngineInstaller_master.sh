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
## Set directory variables and create the directories

# Get the directory of the script file and set varilable
SCRIPT_DIR=$(realpath $(dirname "$0"))

# Define the build directory
DockerEngineInstaller="$SCRIPT_DIR/DockerEngineInstaller"
mkdir -p -m 777 "$DockerEngineInstaller"

# Define the upload directory
upload="$DockerEngineInstaller/upload"
mkdir -p -m 777 "$upload"

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
# Function to install unzip
install_unzip() {
  if ! command -v unzip &> /dev/null; then
  echo "   -----unzip not found, installing unzip-----"
  sudo apt install -y unzip > /dev/null 2>&1
  fi
}


####
# Function to fetch and set Wowza streaming engine Docker versions
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

    # Create menu items for available versions of wse docker images
    local menu_items=()
    for version in "${versions[@]}"; do
        menu_items+=("$version" "")
    done

    # Calculate menu dimensions
    local menu_height=$(( ${#menu_items[@]} / 2 + 7 ))
    menu_height=$(( menu_height > 20 ? 20 : menu_height ))
    local list_height=$(( ${#menu_items[@]} / 2 ))
    list_height=$(( list_height > 10 ? 10 : list_height ))

    # Display a box to select version to use
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
    mkdir -p "$container_dir"
    # Define the SWAG directory
    swag="$container_dir/config"
    mkdir -p -m 777 "$swag" || {
        echo "Error: Failed to create container directory"
        exit 1
    }
}

####
# Function to check if SSL is going to be used, then scan for .jks file, offer to choose an available one
use_ssl=false
check_for_jks() {
  # Step 1: Ask user if they want to use SSL
  if whiptail --title "SSL Configuration" --yesno "Do you want to use SSL? Note: The installer can assist in getting a free domain and SSL. Non SSL config is currently broken for Webserver" 10 60; then
    use_ssl=true
  else
    use_ssl=false
    duckdns=false
    uploaded_jks=false
    chosen_jks_file=false
    create_docker_image
    return 1
  fi

  whiptail --title "SSL Configuration" --msgbox "Starting SSL Configuration... \nSearching for existing SSL Java Key Store (JKS) files in $upload" 10 60

  # Step 2: Find all .jks files
  jks_files=($(ls "$upload"/*.jks 2>/dev/null))
  chosen_jks_file=false
  if [ ${#jks_files[@]} -eq 0 ]; then
    whiptail --title "SSL Configuration" --msgbox "No .jks file/s found." 10 60
    if whiptail --title "SSL Configuration" --yesno "Do you want to upload a JKS file or create a new domain and JKS file?" 10 60 --yes-button "Upload" --no-button "Create"; then
      upload_jks
    else
      duckDNS_create
    fi
  else
    if [ ${#jks_files[@]} -eq 1 ]; then
      jks_file="${jks_files[0]}"
      if whiptail --title "JKS File/s Detected" --yesno "A .jks file $(basename "$jks_file") was detected. Do you want to use this file?" 10 60; then
        chosen_jks_file=true
        ssl_config "$jks_file"
      else
        if whiptail --title "SSL Configuration" --yesno "Do you want to upload a JKS file or create a new domain and JKS file?" 10 60 --yes-button "Upload" --no-button "Create"; then
          upload_jks
        else
          duckDNS_create
        fi
      fi
    else
      # Create a radiolist with the list of .jks files
      menu_options=()
      for file in "${jks_files[@]}"; do
        menu_options+=("$(basename "$file")" "" OFF)
      done
      # Present a list of .jks files to choose from
      while true; do
        jks_file=$(whiptail --title "SSL Configuration" --radiolist "Multiple JKS files found. Choose one:" 20 60 10 "${menu_options[@]}" 3>&1 1>&2 2>&3)
        
        if [ $? -eq 0 ] && [ -n "$jks_file" ]; then
          jks_file="$upload/$jks_file"
          break
        else
          if ! whiptail --title "SSL Configuration" --yesno "You must select a JKS file. Do you want to try again? Use the space button to select." 10 60; then
            whiptail --title "SSL Configuration" --msgbox "No JKS file selected. Exiting." 10 60
              use_ssl=false
              duckdns=false
              uploaded_jks=false
              chosen_jks_file=false
              create_docker_image
            return 1
          fi
        fi
      done
      chosen_jks_file=true
      ssl_config "$jks_file"
    fi
  fi
}

####
# Function to guide DuckDNS domain setup and prep for swag SSL setup
duckDNS_create() {
  duckdns=false
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

    # Show instructions for DuckDNS 
    whiptail --title "DuckDNS Setup" --msgbox "Please: \n\n1. Go to duckdns.org\n2. Create a new domain pointing to: $public_ip\n3. Copy your token\n\nClick OK when ready." $DIALOG_HEIGHT $DIALOG_WIDTH

    # Get domain that was configured in DuckDNS
    while true; do
        jks_duckdns_domain=$(whiptail --title "DuckDNS Domain" --inputbox "Enter your DuckDNS domain (without .duckdns.org):" 8 $DIALOG_WIDTH 3>&1 1>&2 2>&3)
        
        if [[ $? -ne 0 ]]; then
            whiptail --title "Error" --msgbox "Domain input was canceled. Exiting." 8 $DIALOG_WIDTH
              use_ssl=false
              duckdns=false
              uploaded_jks=false
              chosen_jks_file=false
              create_docker_image
            return 1
        elif [[ -z "$jks_duckdns_domain" ]]; then
            whiptail --title "Error" --msgbox "Domain input is required. Please enter a valid DuckDNS domain." 8 $DIALOG_WIDTH
        else
            break
        fi
    done

    # Get DuckDNS token
    while true; do
        duckdns_token=$(whiptail --title "DuckDNS Token" --inputbox "Enter your DuckDNS token:" 8 $DIALOG_WIDTH 3>&1 1>&2 2>&3)
        
        if [[ $? -ne 0 ]]; then
            whiptail --title "Error" --msgbox "Token input was canceled. Exiting." 8 $DIALOG_WIDTH
              use_ssl=false
              duckdns=false
              uploaded_jks=false
              chosen_jks_file=false
              create_docker_image
            return 1
        elif [[ -z "$duckdns_token" ]]; then
            whiptail --title "Error" --msgbox "DuckDNS token is required. Please enter a valid token." 8 $DIALOG_WIDTH
        else
            break
        fi
    done

    # Export variables and append domain
    export jks_duckdns_domain="${jks_duckdns_domain}.duckdns.org" duckdns_token

    # Create temp JKS file
    touch "$upload/${jks_duckdns_domain}.jks"
    # Create jksfile variable
    jks_file="$upload/${jks_duckdns_domain}.jks"

      # Ensure the DNS_CONF_DIR exists
      sudo mkdir -p "$DNS_CONF_DIR"
      # Create and copy duckdns.ini with secure permissions
        if printf "dns_duckdns_token=%s\n" "$duckdns_token" > "$upload/duckdns.ini"; then
            if cp "$upload/duckdns.ini" "$DNS_CONF_DIR/duckdns.ini"; then
                sudo chmod 644 "$DNS_CONF_DIR/duckdns.ini" "$upload/duckdns.ini" && duckdns=true && ssl_config "$jks_file" || {
                    whiptail --title "Error" --msgbox "Failed to set permissions for DuckDNS configuration" 8 $DIALOG_WIDTH
                    rm -f "$upload/duckdns.ini" "$DNS_CONF_DIR/duckdns.ini" "$upload/${jks_duckdns_domain}.jks"
                      use_ssl=false
                      duckdns=false
                      uploaded_jks=false
                      chosen_jks_file=false
                      create_docker_image
                    return 1
                }
            else
                whiptail --title "Error" --msgbox "Failed to copy DuckDNS configuration" 8 $DIALOG_WIDTH
                rm -f "$upload/duckdns.ini" "$upload/${jks_duckdns_domain}.jks"
                  use_ssl=false
                  duckdns=false
                  uploaded_jks=false
                  chosen_jks_file=false
                  create_docker_image
                return 1
            fi
        else
            whiptail --title "Error" --msgbox "Failed to create DuckDNS configuration" 8 $DIALOG_WIDTH
              use_ssl=false
              duckdns=false
              uploaded_jks=false
              chosen_jks_file=false
              create_docker_image
            return 1
        fi
    return 0
}

# Function to upload .jks file
upload_jks() {
  uploaded_jks=false
  while true; do
    if whiptail --title "SSL Configuration" --msgbox "Press [Enter] to continue after uploading the .jks file to $upload..." 10 60; then

      # Find all .jks files
      jks_files=($(ls "$upload"/*.jks 2>/dev/null))
      if [ ${#jks_files[@]} -eq 0 ]; then
        if whiptail --title "SSL Configuration" --yesno "No .jks file found. Would you like to upload again?" 10 60; then
          continue
        else
          whiptail --title "SSL Configuration" --msgbox "You chose not to add a .jks file. Continuing without SSL." 10 60
          use_ssl=false
          duckdns=false
          uploaded_jks=false
          chosen_jks_file=false
          create_docker_image          
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
                use_ssl=false
                duckdns=false
                uploaded_jks=false
                chosen_jks_file=false
                create_docker_image
                return 1
              fi
            fi
          done

          if [ $? -ne 0 ]; then
            whiptail --title "SSL Configuration" --msgbox "You chose not to add a .jks file. Continuing without SSL." 10 60
            use_ssl=false
            duckdns=false
            uploaded_jks=false
            chosen_jks_file=false
            create_docker_image
            return 1
          fi
        fi
        uploaded_jks=true
        ssl_config "$jks_file"
        return 0
      fi
    else
      whiptail --title "SSL Configuration" --msgbox "You chose not to add a .jks file. Continuing without SSL" 10 60
      use_ssl=false
      duckdns=false
      uploaded_jks=false
      chosen_jks_file=false
      create_docker_image
      return 1
    fi
  done
}

####
# Function to configure SSL
ssl_config() {
  # Extract the base name of the jks_file
  jks_file=$(basename "$1")

  # Check if the jks_file variable contains the word "streamlock or duckdns"
  if [[ "$jks_file" == *"streamlock"* ]]; then
    jks_domain="${jks_file%.jks}"
  elif [[ "$jks_file" == *"duckdns"* ]]; then
    jks_domain="${jks_file%.jks}"
  else
    jks_domain=""
  fi
  # Initialize duckdns variable to false
  duckdns=false
  # Capture the domain for the .jks file
  while true; do
    jks_domain=$(whiptail --title "SSL Configuration" --inputbox "Provide the domain for $jks_file file (e.g., myWowzaDomain.com):" 10 60 "$jks_domain" 3>&1 1>&2 2>&3)
    if [ $? -eq 0 ] && [ -n "$jks_domain" ]; then
        # Check if the domain contains 'duckdns.org' and set duckdns variable to true if it does
        if [[ "$jks_domain" == *"duckdns.org"* ]]; then
            duckdns=true
        fi
      break
    else
      if ! whiptail --title "SSL Configuration" --yesno "Domain input is required. Do you want to try again?" 10 60; then
        whiptail --title "SSL Configuration" --msgbox "Domain input cancelled. Continuing without SSL." 10 60
          use_ssl=false
          duckdns=false
          uploaded_jks=false
          chosen_jks_file=false
          create_docker_image
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
          use_ssl=false
          duckdns=false
          uploaded_jks=false
          chosen_jks_file=false
          create_docker_image
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
# Function to create Dockerfile and build Docker image for Wowza Engine
create_docker_image() {
  # Change directory to $DockerEngineInstaller
  cd "$DockerEngineInstaller"
  
  # Create a Dockerfile
  cat <<EOL > Dockerfile
FROM wowzamedia/wowza-streaming-engine-linux:${engine_version}

RUN apt update && apt install -y nano
WORKDIR /usr/local/WowzaStreamingEngine/
RUN ls -la /sbin/

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

    # Edit the Server.xml file to add swagger documentation access
    echo "RUN sed -i 's|<DocumentationServerEnable>false</DocumentationServerEnable>|<DocumentationServerEnable>true</DocumentationServerEnable>|' /usr/local/WowzaStreamingEngine/conf/Server.xml" >> Dockerfile
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

  if $duckdns; then
    SSL_EMAIL=$(whiptail --inputbox "Provide email address for SSL Certificate:" 8 78 --title "ZeroSSL Email" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ] || [ -z "$SSL_EMAIL" ]; then
    whiptail --msgbox "Email address required. Please try again." 8 78 --title "Error"
    SSL_EMAIL=$(whiptail --inputbox "Provide email address for SSL Certificate:" 8 78 --title "ZeroSSL Email" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$SSL_EMAIL" ]; then
      echo "No email provided, exiting install process" >&2
      exit 1
    fi
  fi
  fi
}

check_env_prompt_credentials() {
# Check if .env file exists
if [ -f $container_dir/.env ]; then
  # Read existing values from .env file
  source $container_dir/.env
  # Present a whiptail window with existing data allowing user to make changes
  prompt_credentials "$WSE_MGR_USER" "$WSE_LIC" "$EMAIL"
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
EMAIL=${SSL_EMAIL}
EOL
}

####
# Function to create docker-compose.yml and run docker compose up
create_and_run_docker_compose() {

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
      - TZ=\${TZ}
EOL
  # Conditionally add SSL command block
  if $duckdns; then
    cat <<EOL >> "$container_dir/docker-compose.yml"
      - URL=\${URL}
      - VALIDATION=dns
      - SUBDOMAINS= #optional
      - CERTPROVIDER=zerossl #optional
      - DNSPLUGIN=duckdns #optional
      - DUCKDNSTOKEN=\${DUCKDNSTOKEN}
      - PROPAGATION= #optional
      - EMAIL=\${EMAIL} #optional
      - ONLY_SUBDOMAINS=false #optional
      - EXTRA_DOMAINS= #optional
      - STAGING=false #optional
      - DISABLE_F2B= #optional
      - SWAG_AUTORELOAD=true
EOL
  fi

  cat <<EOL >> "$container_dir/docker-compose.yml"
    volumes:
      - ${swag}:/config
      - ./www:/config/www
    ports:
      - 444:443
      - 80:80
    restart: unless-stopped
  wowza:
    depends_on:
      swag:
        condition: service_started
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
      - engine:/usr/local/WowzaStreamingEngine
      - ${swag}/etc/letsencrypt:/usr/local/WowzaStreamingEngine/conf/ssl
      - ./www:/usr/local/WowzaStreamingEngine/www
    entrypoint: /sbin/entrypoint.sh
    env_file: 
      - ./.env
    environment:
      - WSE_LIC=${WSE_LIC}
      - WSE_MGR_USER=${WSE_MGR_USER}
      - WSE_MGR_PASS=${WSE_MGR_PASS}
  portainer:
    depends_on:
      swag:
        condition: service_started
    image: portainer/portainer-ce:latest
    container_name: portainer
    ports:
      - 9443:9443
      - 8000:9000
    volumes:
      - ${swag}/etc/letsencrypt/live/$jks_domain:/certs/live/$jks_domain:ro
      - ${swag}/etc/letsencrypt/archive/$jks_domain:/certs/archive/$jks_domain:ro
      - portainer_data:/data
      - /var/run/docker.sock:/var/run/docker.sock
EOL
    # Conditionally add SSL command block
  if $use_ssl; then
    cat <<EOL >> "$container_dir/docker-compose.yml"
    command: |-
      --sslcert /certs/live/$jks_domain/fullchain.pem
      --sslkey /certs/live/$jks_domain/privkey.pem
EOL
  fi

  cat <<EOL >> "$container_dir/docker-compose.yml"
    restart: unless-stopped
volumes:
  portainer_data:
    driver: local
  engine:
    driver: local
EOL

  # Run docker compose up
  cd "$container_dir"
  sudo docker compose up -d

  # Wait for the services to start and print logs
  echo "Waiting for services to start..."
  sleep 1  # Adjust the sleep time as needed

  echo "Printing docker compose logs..."
  sudo docker compose logs
}

# Function to convert PEM to PKCS12 and then to JKS
convert_pem_to_jks() {
  echo "Converting ZeroSSL certificate to JKS format ($domain.jks) for use with Wowza Streaming Engine..."
    local domain=$1
    local pem_dir=/usr/local/WowzaStreamingEngine/conf/ssl/archive/$domain
    local jks_dir=/usr/local/WowzaStreamingEngine/conf
    local pkcs12_password=$2
    local jks_password=$3

    # Check if required files are present
    required_files=("cert1.pem" "privkey1.pem" "chain1.pem" "fullchain1.pem")
    timeout=120  # Timeout in seconds
    start_time=$(date +%s)
    total_files=${#required_files[@]}
    files_found=0

   # Check if required files are present inside the Docker container
    required_files=("cert1.pem" "privkey1.pem" "chain1.pem" "fullchain1.pem")
    timeout=120  # Timeout in seconds
    start_time=$(date +%s)
    total_files=${#required_files[@]}
    files_found=0

    echo "Checking for required files..."

    while true; do
        all_files_present=true
        files_found=0
        for file in "${required_files[@]}"; do
            if docker exec "$container_name" test -f "$pem_dir/$file"; then
                files_found=$((files_found + 1))
            else
                all_files_present=false
            fi
        done

        if $all_files_present; then
            echo -ne "\rRequired files found"
            break
        fi

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [ $elapsed_time -ge $timeout ]; then
            echo -ne "\rError: Required files not found within the timeout period"
            return 1
        fi

        # Update echo timer on the same line
        echo -ne "\rElapsed time: $elapsed_time seconds. Files found: $files_found/$total_files"
        sleep 1  # Wait for 1 second before checking again
    done
    
    # Convert PEM to PKCS12 and then to JKS inside the Docker container
    docker exec "$container_name" bash -c "
        openssl pkcs12 -export -in '$pem_dir/fullchain1.pem' -inkey '$pem_dir/privkey1.pem' -out '$jks_dir/$domain.p12' -name '$domain' -passout pass:$pkcs12_password &&
        /usr/local/WowzaStreamingEngine/java/bin/keytool -importkeystore -srckeystore '$jks_dir/$domain.p12' -srcstoretype PKCS12 -srcstorepass $pkcs12_password -destkeystore '$jks_dir/$domain.jks' -deststorepass $jks_password -destkeypass $jks_password -alias '$domain' -noprompt
    "

    if [ $? -eq 0 ]; then
        echo "Successfully converted PEM to JKS"
    else
        echo "Error: Failed to convert PEM to JKS. Please check the $swag/log/letsencrypt/letsencrypt.log file for more information"
        return 1
    fi

    return 0
}

####
# Function to convert uploaded jks file to pem
convert_jks_to_pem() {

echo "Converting $jks_file to CRT format for use with SWAG and Portainer..."

# Check if keytool is installed and install it
    if ! command -v keytool &> /dev/null; then
        echo "keytool could not be found. Installing..."
        sudo apt-get update
        sudo apt-get install -y openjdk-21-jre-headless
    fi
cd $upload
    # Convert JKS to PKCS12
    sudo keytool -importkeystore \
        -srckeystore "$jks_file" \
        -srcstorepass "$jks_password" \
        -srcstoretype JKS \
        -destkeystore keystore.p12 \
        -deststoretype PKCS12 \
        -deststorepass "$jks_password" \
        -destkeypass "$jks_password" \
        -noprompt

# Convert PKCS12 to PEM (certificate only)
sudo openssl pkcs12 -in keystore.p12 -nokeys -out cert.crt -passin pass:$jks_password

# Convert PKCS12 to PEM (private key only)
sudo openssl pkcs12 -in keystore.p12 -nodes -nocerts -out key.key -passin pass:$jks_password

sudo cp cert.crt $swag/etc/letsencrypt/archive/$jks_domain/fullchain1.crt
sudo cp key.key $swag/etc/letsencrypt/archive/$jks_domain/privkey1.key
sudo ln -s $swag/etc/letsencrypt/archive/$jks_domain/fullchain1.crt $swag/etc/letsencrypt/live/$jks_domain/fullchain.crt
sudo ln -s $swag/etc/letsencrypt/archive/$jks_domain/privkey1.key $swag/etc/letsencrypt/live/$jks_domain/privkey.key
}

####
# Function to install Swagger UI
install_swagger() {
  # Download Swagger UI from Wowza
  cd "$container_dir/www"
  wget https://www.wowza.com/downloads/forums/restapidocumentation/RESTAPIDocumentationWebpage.zip
  unzip -o RESTAPIDocumentationWebpage.zip -d swagger
  rm RESTAPIDocumentationWebpage.zip

  # Replace the URL in the swagger/index.html file
  if $use_ssl; then
  sed -i "s|http://localhost:8089/api-docs|https://$jks_domain:8089/api-docs|g" swagger/index.html
  else
  sed -i "s|http://localhost:8089/api-docs|http://$public_ip:8089/api-docs|g" swagger/index.html
  fi
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

  # Copy the .jks file into the wse container
  if ! $duckdns; then
    sudo docker cp $upload/$jks_file $container_name:/usr/local/WowzaStreamingEngine/conf/$jks_file
  fi

  # Restart docker stack to apply changes
  cd $container_dir
  sudo docker compose restart
}

####
# Function to create HTML instructions
create_html_instructions() {
  local public_ip=$(curl -s https://api.ipify.org)
  # Create HTML instructions
  if $use_ssl; then
  cat <<EOL > "$container_dir/www/instructions.html"
<!DOCTYPE html>
<html>
<head>
  <title>WSE SWAG Portainer in Docker</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      background-color: #f9f9f9;
      color: #333;
      margin: 0;
      padding: 0;
    }
    header {
      background-color: #ff6600;
      color: white;
      padding: 20px;
      text-align: center;
    }
    .container {
      padding: 20px;
    }
    h1 {
      color: #f9f9f9;
    }    
    h2 {
      color: #ff6600;
    }
    p, ul {
      font-size: 16px;
      line-height: 1.6;
    }
    a {
      color: #ff6600;
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
    .logo {
      width: 50px;
      vertical-align: middle;
      margin-right: 10px;
    }
    .section {
      margin-bottom: 40px;
    }
  </style>
</head>
<body>
  <header>
    <h1>Wowza Streaming Engine, SWAG and Portainer in Docker</h1>
  </header>
  <div class="container">
    <div class="section">
      <h2>Wowza Streaming Engine</h2>
      <img src="https://www.wowza.com/wp-content/uploads/Wowza-logo-transparent.png" alt="Wowza Logo" class="logo">
      <p>Access the Wowza Streaming Engine Manager at: <a href="https://$jks_domain:8090" target="_blank">https://$jks_domain:8090</a></p>
      <p>Access the Swagger UI for REST API at: <a href="https://$jks_domain:444/swagger/" target="_blank">https://$jks_domain:444/swagger</a></p>
      <p>To manage the Engine files, use the following symlinks in the <strong>$container_dir</strong> directory:</p>
      <ul>
        <li>Engine_lib</li>
        <li>Engine_conf</li>
        <li>Engine_logs</li>
        <li>Engine_content</li>
        <li>Engine_transcoder</li>
        <li>Engine_manager</li>
      </ul>
      <p>Use the commands below to edit files directly, copy files in and out of the container:</p>
      <ul>
        <li>Edit files directly: <code>sudo nano Engine_xxxx/[file_name]</code></li>
        <li>Copy files out: <code>sudo cp Engine_xxxx/[file_name] [file_name]</code></li>
        <li>Copy files in: <code>sudo cp [file_name] Engine_xxxx/[file_name]</code></li>
      </ul>
      <p>NOTE: Container must be restarted for changes to take effect:</p>
      <p>To manage the state of the docker containers, use the following commands:</p>
      <ul>
        <li>Stop and destroy the Docker Wowza container: <code>cd $container_dir && sudo docker compose down --rmi 'all' && cd $SCRIPT_DIR</code></li>
        <li>Stop the container without destroying it: <code>cd $container_dir && sudo docker compose stop && cd $SCRIPT_DIR</code></li>
        <li>Start the container after stopping it: <code>cd $container_dir && sudo docker compose start && cd $SCRIPT_DIR</code></li>
      </ul>
      <p>To delete volumes, use the following command:</p>
      <ul>
        <li><code>sudo docker volume ls</code></li>
        <li><code>sudo docker volume rm "volume name"</code></li>
      </ul>
      <p>To access the container directly, type: 
      <ul>
        <li><code>sudo docker exec -it $container_name bash</code></li>
      </ul>
    </div>

    <div class="section">
      <h2>Portainer</h2>
      <img src="https://w7.pngwing.com/pngs/112/58/png-transparent-portainer-wordmark-hd-logo.png" alt="Portainer Logo" class="logo">
      <p>Access the Portainer web interface at: <a href="https://$jks_domain:9443" target="_blank">https://$jks_domain:9443</a></p>
      <p>Portainer is a lightweight docker management UI that allows you to easily manage your Docker containers, images, networks, and volumes.</p>
      <p>For more information, visit the <a href="https://www.portainer.io" target="_blank">Portainer website</a>.</p>
    </div>

    <div class="section">
      <h2>SWAG</h2>
      <img src="https://docs.linuxserver.io/assets/icon.svg" alt="SWAG Logo" class="logo">
      <p>Access the SWAG webserver at: <a href="https://$jks_domain:444" target="_blank">https://$jks_domain:444</a></p>
      <p>SWAG - Secure Web Application Gateway (formerly known as letsencrypt, no relation to Let's Encrypt™) sets up an 
      Nginx webserver and reverse proxy with php support and a built-in certbot client that automates free SSL server certificate generation 
      and renewal processes (Let's Encrypt and ZeroSSL). It also contains fail2ban for intrusion prevention.
      </p>
      <p>To manage the webserver and pages you can access the files in <strong>$container_dir/www</strong></p>
      <p>For more information, visit the <a href="https://github.com/linuxserver/docker-swag" target="_blank">SWAG github</a>.</p>
    </div>
  </div>
</body>
</html>
EOL
  else
  cat <<EOL > "$container_dir/www/instructions.html"
<!DOCTYPE html>
<html>
<head>
  <title>WSE SWAG Portainer in Docker</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      background-color: #f9f9f9;
      color: #333;
      margin: 0;
      padding: 0;
    }
    header {
      background-color: #ff6600;
      color: white;
      padding: 20px;
      text-align: center;
    }
    .container {
      padding: 20px;
    }
    h1 {
      color: #f9f9f9;
    }    
    h2 {
      color: #ff6600;
    }
    p, ul {
      font-size: 16px;
      line-height: 1.6;
    }
    a {
      color: #ff6600;
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
    .logo {
      width: 50px;
      vertical-align: middle;
      margin-right: 10px;
    }
    .section {
      margin-bottom: 40px;
    }
  </style>
</head>
<body>
  <header>
    <h1>Wowza Streaming Engine, SWAG and Portainer in Docker</h1>
  </header>
  <div class="container">
    <div class="section">
      <h2>Wowza Streaming Engine</h2>
      <img src="https://www.wowza.com/wp-content/uploads/Wowza-logo-transparent.png" alt="Wowza Logo" class="logo">
      <p>Access the Wowza Streaming Engine Manager at: <a href="http://$public_ip:8088" target="_blank">http://$public_ip:8088</a></p>
      <!-- <p>Access the Swagger UI for REST API at: <a href="http://$public_ip/swagger/" target="_blank">http://$public_ip/swagger</a></p> -->
      <p>To manage the Engine files, use the following symlinks in the <strong>$container_dir</strong> directory:</p>
      <ul>
        <li>Engine_lib</li>
        <li>Engine_conf</li>
        <li>Engine_logs</li>
        <li>Engine_content</li>
        <li>Engine_transcoder</li>
        <li>Engine_manager</li>
      </ul>
      <p>Use the commands below to edit files directly, copy files in and out of the container:</p>
      <ul>
        <li>Edit files directly: <code>sudo nano Engine_xxxx/[file_name]</code></li>
        <li>Copy files out: <code>sudo cp Engine_xxxx/[file_name] [file_name]</code></li>
        <li>Copy files in: <code>sudo cp [file_name] Engine_xxxx/[file_name]</code></li>
      </ul>
      <p>NOTE: Container must be restarted for changes to take effect: <code>cd $container_dir && sudo docker restart $container_name && cd $SCRIPT_DIR</code></p>
      <p>To restart other containders, use swag or portainer in the same command</p>
      <p>To manage the state of the docker containers, use the following commands:</p>
      <ul>
        <li>Stop and destroy the Docker Wowza, swag and portainer container stack: <code>cd $container_dir && sudo docker compose down --rmi 'all' && cd $SCRIPT_DIR</code></li>
        <li>Stop the container stack without destroying it: <code>cd $container_dir && sudo docker compose stop && cd $SCRIPT_DIR</code></li>
        <li>Start the container stack after stopping it: <code>cd $container_dir && sudo docker compose start && cd $SCRIPT_DIR</code></li>
        <li>Restart the container stack: <code>cd $container_dir && sudo docker compose restart && cd $SCRIPT_DIR</code></li>
      </ul>
      <p>To delete volumes, use the following command:</p>
      <ul>
        <li><code>sudo docker volume ls</code></li>
        <li><code>sudo docker volume rm "volume name"</code></li>
      </ul>
      <p>To access the container directly, type:
      <ul>
        <li><code>sudo docker exec -it $container_name bash</code></li>
      </ul>
      <p>To nuke the whole thing and start over, use the following commands:</p>
      <ul>
        <li>sudo docker system prune -a --volumes -f</li>
      </ul>
    </div>

    <div class="section">
      <h2>Portainer</h2>
      <img src="https://w7.pngwing.com/pngs/112/58/png-transparent-portainer-wordmark-hd-logo.png" alt="Portainer Logo" class="logo">
      <p>Access the Portainer web interface at: <a href="http://$public_ip:8000" target="_blank">http://$public_ip:8000</a></p>
      <p>Portainer is a lightweight docker management UI that allows you to easily manage your Docker containers, images, networks, and volumes.</p>
      <p>For more information, visit the <a href="https://www.portainer.io" target="_blank">Portainer website</a>.</p>
    </div>

    <!-- <div class="section">
       <h2>SWAG</h2>
      <img src="https://docs.linuxserver.io/assets/icon.svg" alt="SWAG Logo" class="logo">
      <p>Access the SWAG webserver at: <a href="http://$public_ip" target="_blank">http://$public_ip</a></p>
      <p>SWAG is a webserver and a free SSL certificate bot that provides SSL certificates for your Wowza Streaming Engine and Manager.</p>
      <p>To manage the webserver and pages you can access the files in <strong>$container_dir/www</strong></p>
      <p>For more information, visit the <a href="https://github.com/linuxserver/docker-swag" target="_blank">SWAG github</a>.</p>
    </div> -->
  </div>
</body>
</html>
EOL
  fi
}

# Get the private IP address
private_ip=$(ip route get 1 | awk '{print $7;exit}')
   # Get public IP with retry
    for i in {1..3}; do
        public_ip=$(curl -s -f https://api.ipify.org)
        [[ $? -eq 0 && -n "$public_ip" ]] && break
        sleep 2
    done

##### Start the Installation #####
install_docker
install_jq
install_unzip
fetch_and_set_wowza_versions
if [ $? -ne 0 ]; then
  echo -e "${w}Installation cancelled by user."
  exit 1
fi

check_for_jks # runs upload_jks, ssl_config, duckDNS_create
create_docker_image
check_env_prompt_credentials 
create_and_run_docker_compose

# Create symlinks for Engine directories
engine_volume=$(sudo docker volume ls --format '{{.Name}}' | grep '_engine')
sudo ln -sf /var/lib/docker/volumes/$engine_volume/_data/conf/ $container_dir/Engine_conf
sudo ln -sf /var/lib/docker/volumes/$engine_volume/_data/logs/ $container_dir/Engine_logs
sudo ln -sf /var/lib/docker/volumes/$engine_volume/_data/content/ $container_dir/Engine_content
sudo ln -sf /var/lib/docker/volumes/$engine_volume/_data/transcoder/ $container_dir/Engine_transcoder
sudo ln -sf /var/lib/docker/volumes/$engine_volume/_data/manager/ $container_dir/Engine_manager
sudo ln -sf /var/lib/docker/volumes/$engine_volume/_data/lib /$container_dir/Engine_lib

if $duckdns; then
  convert_pem_to_jks "$jks_domain" "$jks_password" "$jks_password"
fi
if $uploaded_jks || $chosen_jks_file; then
  convert_jks_to_pem
fi

install_swagger
cleanup
create_html_instructions

if $use_ssl; then
echo -e "${w}For instructions on using the installed software, please visit ${yellow}https://$jks_domain:444/instructions.html${NOCOLOR}"
else
echo -e "${w}For instructions on using the installed software, please open ${yellow}$container_dir/www/instructions.html${NOCOLOR}"
fi

# Prompt user to delete installer script
if whiptail --title "Installation complete" --yesno "The installer has completed the installation of 
Wowza Streaming Engine, SWAG and Portainer.

Do you want to delete this installer script?" 16 78; then
  rm $SCRIPT_DIR/DockerEngineInstaller.sh
fi