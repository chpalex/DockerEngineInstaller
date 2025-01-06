#!/bin/bash

tuning () {
local engine_conf_dir=$1

# Server Tuning #
echo "Tuning Network Sockets and Server Threads"
# Change ReceiveBufferSize and SendBufferSize values to 0 for <NetConnections> and <MediaCasters>
sed -i 's|<ReceiveBufferSize>.*</ReceiveBufferSize>|<ReceiveBufferSize>0</ReceiveBufferSize>|g' "$engine_conf_dir/VHost.xml"
sed -i 's|<SendBufferSize>.*</SendBufferSize>|<SendBufferSize>0</SendBufferSize>|g' "$engine_conf_dir/VHost.xml"

# Check CPU thread count
cpu_thread_count=$(nproc)

# Calculate pool sizes with limits
handler_pool_size=$((cpu_thread_count * 60))
transport_pool_size=$((cpu_thread_count * 40))

# Apply limits
if [ "$handler_pool_size" -gt 4096 ]; then
  handler_pool_size=4096
fi

if [ "$transport_pool_size" -gt 4096 ]; then
  transport_pool_size=4096
fi

# Update Server.xml with new pool sizes
sed -i 's|<HandlerThreadPool>.*</HandlerThreadPool>|<HandlerThreadPool><PoolSize>'"$handler_pool_size"'</PoolSize></HandlerThreadPool>|' "$engine_conf_dir/Server.xml"
sed -i 's|<TransportThreadPool>.*</TransportThreadPool>|<TransportThreadPool><PoolSize>'"$transport_pool_size"'</PoolSize></TransportThreadPool>|' "$engine_conf_dir/Server.xml"

# Configure Demo live stream
if whiptail --title "Demo Live Stream" --yesno "Do you want to add a demo live stream on Engine?" 10 60; then
  # Create a demo live stream
  sed -i '/<\/ServerListeners>/i \
            <ServerListener>\
              <BaseClass>com.wowza.wms.module.ServerListenerStreamDemoPublisher</BaseClass>\
            </ServerListener>' "$engine_conf_dir/Server.xml"
  
  # Find the line number of the closing </Properties> tag directly above the closing </Server> tag
  line_number=$(awk '/<\/Properties>/ {p=NR} /<\/Server>/ && p {print p; exit}' "$engine_conf_dir/Server.xml")

  # Insert the new property at the found line number
  if [ -n "$line_number" ]; then
    sed -i "${line_number}i <Property>\n<Name>streamDemoPublisherConfig</Name>\n<Value>appName=live,srcStream=sample.mp4,dstStream=myStream,sendOnMetadata=true</Value>\n\Type>String</Type>\n</Property>" "$engine_conf_dir/Server.xml"
  fi
fi

# Edit log4j2-config.xml to comment out serverError appender
sed -i 's|<AppenderRef ref="serverError" level="warn"/>|<!-- <AppenderRef ref="serverError" level="warn"/> -->|g' "$engine_conf_dir/log4j2-config.xml"

# Edit entrypoint.sh to copy conf directory to the bind mount at runtime

}
