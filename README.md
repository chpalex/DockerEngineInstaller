# DockerEngineInstaller
Install Wowza Streaming Engine, SWAG and Portainer in Docker

The script does the following:
- create a directory DockerEngineInstaller, DockerEngineInstaller/upload, DockerEngineInstaller/config
- check for docker and jq, install if not installed
- retrieve a list of available WSE docker images and present them to the user to select
- asks if the user wants to use SSL
- check if any jks are available and offers the user to use one
- capture jks password for future use
- create tomcat.properties in the upload directory
- propmpt user to upload ssl if they chose not to use anything
- directs user to create a free domain through duckdns.org and capture the duckdns token for future use
- creates placeholder jks file
- create duckdns.ini with the token to use with SWAG to obtain SSL cert
- create a tomcat.properties file to use with WSEM
- create a custom WSE docker image with tuning for cores, network, SSL (if selected) and ports
- prompt user for Engine Manager user, password and key for WSE as well as email address for SSL configuration
- run a docker compose command to spin up the custom Engine image, SWAG and Portainer
- convert the SSL .pem file to jks in WSE
- add the pem files to portainer for SSL access
- download and install the swagger doc server (stil working on authenticated access)
- create html page with instructions on how to use this software 
- create soft links to WSE conf, logs, content, transcoder, managaer and lib to alow full management of the software with modules
