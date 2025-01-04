#!/bin/bash

tuning () {
# Server Tuning #
echo "Tuning Network Sockets and Server Threads"
# Change ReceiveBufferSize and SendBufferSize values to 0 for <NetConnections> and <MediaCasters>
sed -i 's|<ReceiveBufferSize>.*</ReceiveBufferSize>|<ReceiveBufferSize>0</ReceiveBufferSize>|g' "$BASE_DIR/VHost.xml"
sed -i 's|<SendBufferSize>.*</SendBufferSize>|<SendBufferSize>0</SendBufferSize>|g' "$BASE_DIR/VHost.xml"

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
sed -i 's|<HandlerThreadPool>.*</HandlerThreadPool>|<HandlerThreadPool><PoolSize>'"$handler_pool_size"'</PoolSize></HandlerThreadPool>|' "$BASE_DIR/Server.xml"
sed -i 's|<TransportThreadPool>.*</TransportThreadPool>|<TransportThreadPool><PoolSize>'"$transport_pool_size"'</PoolSize></TransportThreadPool>|' "$BASE_DIR/Server.xml"

# Configure Demo live stream
read -p "Do you want to add a demo live stream on Engine? (y/n): " demo_stream
if [ "$demo_stream" = "y" ]; then
  echo "Adding demo live stream myStream to the Engine"
  # Create a demo live stream
  sed -i '/<\/ServerListeners>/i \
            <ServerListener>\
              <BaseClass>com.wowza.wms.module.ServerListenerStreamDemoPublisher</BaseClass>\
            </ServerListener>' "$BASE_DIR/Server.xml"
  
  # Find the line number of the closing </Properties> tag directly above the closing </Server> tag
  line_number=$(awk '/<\/Properties>/ {p=NR} /<\/Server>/ && p {print p; exit}' "$BASE_DIR/Server.xml")

  # Insert the new property at the found line number
  if [ -n "$line_number" ]; then
    sed -i "${line_number}i <Property>\n<Name>streamDemoPublisherConfig</Name>\n<Value>appName=live,srcStream=sample.mp4,dstStream=myStream,sendOnMetadata=true</Value>\n<Type>String</Type>\n</Property>" "$BASE_DIR/Server.xml"
  fi
fi
  # Edit log4j2-config.xml to comment out serverError appender
  sed -i 's|<AppenderRef ref="serverError" level="warn"/>|<!-- <AppenderRef ref="serverError" level="warn"/> -->|g' "$BASE_DIR/log4j2-config.xml"

}
