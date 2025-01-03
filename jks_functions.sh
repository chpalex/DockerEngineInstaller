#!/bin/bash

# Function to scan for .jks file
check_for_jks() {
  echo "Files found in $BASE_DIR:"
  ls -1 "$BASE_DIR"

  # Find the .jks file
  jks_file=$(ls "$BASE_DIR"/*.jks 2>/dev/null | head -n 1)
  if [ -z "$jks_file" ]; then
    echo "No .jks file found."
    upload_jks
  else
    jks_file=$(basename "$jks_file")
    read -p "A .jks file ($jks_file) was detected. Do you want to use this file? (y/n): " use_detected_jks
    case $use_detected_jks in
      [Yy]* )
        ssl_config
        ;;
      [Nn]* )
        upload_jks
        ;;
      * )
        echo "Please answer yes or no."
        check_for_jks
        ;;
    esac
  fi
}

# Function to configure SSL
ssl_config() {
  read -p "Provide the domain for .jks file (e.g., myWowzaDomain.com): " jks_domain
  read -s -p "Please enter the .jks password (to establish https connection to Wowza Manager): " jks_password
  echo

  # Setup Engine to use SSL for streaming and Manager access #
  # Create the tomcat.properties file
  echo "   -----Creating tomcat.properties file-----"
  cat <<EOL > "$BASE_DIR/tomcat.properties"
httpsPort=8090
httpsKeyStore=/usr/local/WowzaStreamingEngine/conf/${jks_file}
httpsKeyStorePassword=${jks_password}
#httpsKeyAlias=[key-alias]
EOL

  # Change the <Port> line to have only 1935,554 ports
  sed -i 's|<Port>1935,80,443,554</Port>|<Port>1935,554</Port>|' "$BASE_DIR/VHost.xml"
  
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
  </HostPort>' "$BASE_DIR/VHost.xml"

  # Edit the VHost.xml file to include the new TestPlayer block with the jks_domain
  sed -i '/<\/Manager>/i \
  <TestPlayer>\
      <IpAddress>'${jks_domain}'</IpAddress>\
      <Port>443</Port>\
      <SSLEnable>true</SSLEnable>\
  </TestPlayer>' "$BASE_DIR/VHost.xml"
  
  # Edit the Server.xml file to include the JKS and password information
  sed -i 's|<Enable>false</Enable>|<Enable>true</Enable>|' "$BASE_DIR/Server.xml"
  sed -i 's|<KeyStorePath></KeyStorePath>|<KeyStorePath>/usr/local/WowzaStreamingEngine/conf/'${jks_file}'</KeyStorePath>|' "$BASE_DIR/Server.xml"
  sed -i 's|<KeyStorePassword></KeyStorePassword>|<KeyStorePassword>'${jks_password}'</KeyStorePassword>|' "$BASE_DIR/Server.xml"
  sed -i 's|<IPWhiteList>127.0.0.1</IPWhiteList>|<IPWhiteList>*</IPWhiteList>|' "$BASE_DIR/Server.xml"
}

# Function to upload .jks file
upload_jks() {
  read -p "Do you want to upload a .jks file? (y/n): " upload_jks
  case $upload_jks in
    [Yy]* )
      while true; do
        read -p "Press [Enter] to continue after uploading the .jks file to $BASE_DIR..." 

        # Find the .jks file
        jks_file=$(ls "$BASE_DIR"/*.jks 2>/dev/null | head -n 1)
        if [ -z "$jks_file" ]; then
          read -p "No .jks file found. Would you like to upload again? (y/n): " upload_again
          case $upload_again in
            [Yy]* )
              read -p "Press [Enter] to continue after uploading the files..."
              ;;
            [Nn]* )
              echo "You chose not to add a .jks file. Moving on to tuning."
              return 1
              ;;
            * )
              echo "Please answer yes or no."
              ;;
          esac
        else
          check_for_jks
          return 0
        fi
      done
      ;;
    [Nn]* )
      echo "You chose not to add a .jks file. Moving on to tuning."
      return 1
      ;;
    * )
      echo "Please answer yes or no."
      upload_jks
      ;;
  esac
}
