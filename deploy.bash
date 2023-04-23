#!/bin/bash
# shellcheck shell=bash

#######################################
# Execute a command on nanstis.ch
# Arguments:
#   1 -> a (to-be-evaluated) command to execute on the remote host
#######################################
function send() {
    ssh ${host} "${1}"
}

#######################################
# Clone a repository to a given path on the remote host
# Arguments:
#   1 -> repository url
#   2 -> path of the cloned repository
#######################################
function clone() {
    send "gh repo clone $1 $2"
}

#######################################
# execute a given npm script inside the remote host's application
# Arguments:
#   1 -> the npm script to run
#######################################
function npm_client() {
  send "npm $1 --prefix ${client_destination}"
}

#######################################
# execute a given npm script inside the remote client application
# Arguments:
#   1 -> the npm script to run
#######################################
function npm_server() {
  send "npm $1 --prefix ${server_destination}"
}


#######################################
# execute a given npm script inside both applications
# Arguments:
#   1
#######################################
function npm_common() {
  echo "Executing npm ${1} on server..."
  npm_server "${1}"
  echo "Executing npm ${1} on client..."
  npm_client "${1}"
}

#######################################
# Create a service file
#
# Globals:
#   base_path
# Arguments:
#   1 -> local file path
#   2 -> remote destination
#######################################
function copy() {
  scp $1 ${host}:$2
}

#######################################
# Get relative path of a project's file
# Globals:
#   base_path
# Arguments:
#   1 -> file path from project's root
#######################################
function get() {
    echo "${base_path}/${1}"
}

#######################################
# Clears the terminal before printing the description of next command
# Arguments:
#   1 -> description of the next command
#######################################
function describe(){
  reset
  echo "${1}"
}

#######################################
# description
# Globals:
#   client_name
#   server_name
#   destination
#   server_destination
#   client_destination
#   host
#
# Arguments:
#  None
#######################################
function main() {
  base_path=$(realpath --relative-to="$(pwd)" /opt/bash/)

  local server_repository="https://github.com/nanstis/nanstis-server.git"
  local client_repository="https://github.com/nanstis/nanstis-client.git"

  local client_name="n-client"
  local server_name="n-server"
  local nginx_name="nanstis"

  local destination="/var/www/deploy"

  local service_destination="/etc/systemd/system"
  local nginx_destination="/etc/nginx/sites-available"

  host=root@nanstis.ch
  server_destination=${destination}/${server_name}
  client_destination=${destination}/${client_name}

  describe "Removing previous installations..."
  send "rm -r ${destination}"
  send "mkdir ${destination}"
  send "rm /etc/nginx/sites-enabled/${nginx_name}"

  describe "Cloning server..."
  clone "${server_repository}" ${server_destination}

  describe "Cloning client..."
  clone "${client_repository}" ${client_destination}
  describe "Copying client environment variables..."
  copy ~/.env/.env.client ${client_destination}/.env

  describe "Installing dependencies..."
  npm_common "install"

  describe "Bundling for production..."
  npm_common "run-script build"

  copy ~/.env/.env.server ${server_destination}/dist/.env

  send "mkdir -p ${server_destination}/dist/public/logs"
  send "mkdir ${server_destination}/dist/public/uploads"

  describe "Giving permissions to correct users"
  send "chown www-data -R ${client_destination}"
  send "chown nanstis -R ${server_destination}"
  send "chmod +x ${server_destination}/dist/index.js"

  describe "Sending service configuration file..."
  cat <<EOF > ${server_name}.service
[Unit]
Description=nanstis.ch
After=network.target

[Service]
User=nanstis
WorkingDirectory=${server_destination}/dist
Environment=NODE_ENV=production
ExecStart=/home/nanstis/.nvm/versions/node/v20.0.0/bin/node index.js
Restart=always
SyslogIdentifier=nanstis-api

[Install]
WantedBy=multi-user.target
EOF

  copy "$(get n-server.service)" ${service_destination}

  describe "Sending nginx configuration file..."
  copy "$(get nanstis.nginx)" ${nginx_destination}/${nginx_name}
  send "ln -s ${nginx_destination}/${nginx_name} /etc/nginx/sites-enabled"


  send "systemctl daemon-reload"
  send "systemctl enable ${server_name}"
  send "systemctl start ${server_name}"

  send "systemctl restart nginx"
}

main "$@"
