#!/bin/bash

# Function to scan for .jks file
check_for_jks() {
  whiptail --title "SSL Configuration" --msgbox "Starting SSL Configuration\nSearching for existing SSL Java Key Store (JKS) files in $BASE_DIR" 10 60

  # Find all .jks files
  jks_files=($(ls "$BASE_DIR"/*.jks 2>/dev/null))
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
local jks_file="$1"

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

  cat <<EOL > "$BASE_DIR/tomcat.properties"
httpsPort=8090
httpsKeyStore=/usr/local/WowzaStreamingEngine/conf/${jks_file}
httpsKeyStorePassword=${jks_password}
#httpsKeyAlias=[key-alias]
EOL

  # Change the <Port> line to have only 1935,554 ports
  sed -i 's|<Port>1935,80,443,554</Port>|<Port>1935,554</Port>|' "$engine_conf_dir/VHost.xml"

  # Edit the VHost.xml file to include the new HostPort block with the JKS and password information
  sed -i '/<\/HostPortList>/i \
  <HostPort>\
      <Name>Autoconfig SSL Streaming</Name>\
      <Type>Streaming</Type>\
      <ProcessorCount>\${com.wowza.wms.TuningAuto}</ProcessorCount>\
      <IpAddress>*</IpAddress>\
      <Port>443</Port>\
      <HTTPIdent2Response></HTTPIdent2Response>\
      <SSLConfig>\
          <KeyStorePath>/usr/local/WowzaStreamingEngine/conf/'${jks_file}'</KeyStorePath>\
          <KeyStorePassword>'${jks_password}'</KeyStorePassword>\
          <KeyStoreType>JKS</KeyStoreType>\
          <DomainToKeyStoreMapPath></DomainToKeyStoreMapPath>\
          <SSLProtocol>TLS</SSLProtocol>\
          <Algorithm>SunX509</Algorithm>\
          <CipherSuites></CipherSuites>\
          <Protocols></Protocols>\
          <AllowHttp2>true</AllowHttp2>\
      </SSLConfig>\
      <SocketConfiguration>\
          <ReuseAddress>true</ReuseAddress>\
          <ReceiveBufferSize>65000</ReceiveBufferSize>\
          <ReadBufferSize>65000</ReceiveBufferSize>\
          <SendBufferSize>65000</SendBufferSize>\
          <KeepAlive>true</KeepAlive>\
          <AcceptorBackLog>100</AcceptorBackLog>\
      </SocketConfiguration>\
      <HTTPStreamerAdapterIDs>cupertinostreaming,smoothstreaming,sanjosestreaming,dvrchunkstreaming,mpegdashstreaming</HTTPStreamerAdapterIDs>\
      <HTTPProviders>\
          <HTTPProvider>\
              <BaseClass>com.wowza.wms.http.HTTPCrossdomain</BaseClass>\
              <RequestFilters>*crossdomain.xml</RequestFilters>\
              <AuthenticationMethod>none</AuthenticationMethod>\
          </HTTPProvider>\
          <HTTPProvider>\
              <BaseClass>com.wowza.wms.http.HTTPClientAccessPolicy</BaseClass>\
              <RequestFilters>*clientaccesspolicy.xml</RequestFilters>\
              <AuthenticationMethod>none</AuthenticationMethod>\
          </HTTPProvider>\
          <HTTPProvider>\
              <BaseClass>com.wowza.wms.http.HTTPProviderMediaList</BaseClass>\
              <RequestFilters>*jwplayer.rss|*jwplayer.smil|*medialist.smil|*manifest-rtmp.f4m</RequestFilters>\
              <AuthenticationMethod>none</AuthenticationMethod>\
          </HTTPProvider>\
          <HTTPProvider>\
              <BaseClass>com.wowza.wms.webrtc.http.HTTPWebRTCExchangeSessionInfo</BaseClass>\
              <RequestFilters>*webrtc-session.json</RequestFilters>\
              <AuthenticationMethod>none</AuthenticationMethod>\
          </HTTPProvider>\
          <HTTPProvider>\
              <BaseClass>com.wowza.wms.http.HTTPServerVersion</BaseClass>\
              <RequestFilters>*ServerVersion</RequestFilters>\
              <AuthenticationMethod>none</AuthenticationMethod>\
          </HTTPProvider>\
      </HTTPProviders>\
  </HostPort>' "$engine_conf_dir/VHost.xml"

  # Edit the VHost.xml file to include the new TestPlayer block with the jks_domain
  sed -i '/<\/Manager>/i \
  <TestPlayer>\
      <IpAddress>'${jks_domain}'</IpAddress>\
      <Port>443</Port>\
      <SSLEnable>true</SSLEnable>\
  </TestPlayer>' "$engine_conf_dir/VHost.xml"

  # Edit the Server.xml file to include the JKS and password information
  sed -i 's|<Enable>false</Enable>|<Enable>true</Enable>|' "$engine_conf_dir/Server.xml"
  sed -i 's|<KeyStorePath></KeyStorePath>|<KeyStorePath>/usr/local/WowzaStreamingEngine/conf/'${jks_file}'</KeyStorePath>|' "$engine_conf_dir/Server.xml"
  sed -i 's|<KeyStorePassword></KeyStorePassword>|<KeyStorePassword>'${jks_password}'</KeyStorePassword>|' "$engine_conf_dir/Server.xml"
  sed -i 's|<IPWhiteList>127.0.0.1</IPWhiteList>|<IPWhiteList>*</IPWhiteList>|' "$engine_conf_dir/Server.xml"

  # Copy the .jks file to the Engine conf directory
  if [ -n "$jks_file" ] && [ -f "$BASE_DIR/$jks_file" ]; then
    cp "$BASE_DIR/$jks_file" "$engine_conf_dir/$jks_file"
  else
    exit 1
  fi
echo ".jks file copied to Engine conf directory"
}

# Function to upload .jks file
upload_jks() {
  while true; do
    if whiptail --title "SSL Configuration" --yesno "Do you want to upload a .jks file?" 10 60; then
      whiptail --title "SSL Configuration" --msgbox "Press [Enter] to continue after uploading the .jks file to $BASE_DIR..." 10 60

      # Find all .jks files
      jks_files=($(ls "$BASE_DIR"/*.jks 2>/dev/null))
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
