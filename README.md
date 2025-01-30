# DockerEngineInstaller
Install Wowza Streaming Engine, SWAG and Portainer in Docker

The script does the following:
- create the following directories DockerEngineInstaller, DockerEngineInstaller/upload, DockerEngineInstaller/config
- check for docker and jq, install if not installed
- retrieve a list of available WSE docker images and present them to the user to select
- asks if the user wants to use SSL if no, then skip all ssl prompts and config
- Check for JKS and CHOSE JKS
- check if any jks are available and offers the user to use one
- capture jks password for future use
- capture jks domain for future use
- create tomcat.properties in the upload directory
- UPLOAD SSL 
- propmpt user to upload ssl if they chose not to use an available jks on disk or duckdns
- converts the jks to crt for webserver and portainer
- install keytool (this requires java, install openjdk-21-jre-headless)
- copy resulting files to swag container and connect to portainer for https access
- DuckDNS SSL
- directs user to create a free domain through duckdns.org and capture the duckdns token for future use
- creates placeholder jks file
- convert pem files from zerossl into jks and copy it to Engine
- create duckdns.ini with the token to use with SWAG to obtain SSL cert
- create a tomcat.properties file to use with WSEM
- create a custom WSE docker image with tuning for cores, network, SSL (if selected) and ports
- prompt user for Engine Manager user, password and key for WSE as well as email address for DuckDNS configuration
- run a docker compose command to spin up the custom Engine image, SWAG and Portainer
- download and install the swagger doc server (stil working on authenticated access)
- create html page with instructions on how to use this software 
- create soft links to WSE conf, logs, content, transcoder, managaer and lib to alow full management of the software with modules
