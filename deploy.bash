#!/bin/bash
# shellcheck shell=bash

#######################################
# Execute a command on remote host
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
# Execute a given npm script inside the remote client application
# Arguments:
#   1 -> the npm script to run
#######################################
function npm_client() {
  send "npm $1 --prefix ${client_destination}"
}

#######################################
# Execute a given npm script inside the remote server application
# Arguments:
#   1 -> the npm script to run
#######################################
function npm_server() {
  send "npm $1 --prefix ${server_destination}"
}

#######################################
# Execute a given npm script inside both applications
# Arguments:
#   1 -> the npm script to run
#######################################
function npm_common() {
  npm_server "${1}"
  npm_client "${1}"
}

#######################################
# Create a service file
# Globals:
#   base_path
# Arguments:
#   1 -> local file path
#   2 -> remote destination
#######################################
function copy() {
  scp "${1}" ${host}:"${2}"
}

#######################################
# Get relative path for a file inside this directory
# Globals:
#   base_path
# Arguments:
#   1 -> file path from project's root
#######################################
function get() {
    echo "${base_path}/${1}"
}

#######################################
# Removes previous installations
# Globals:
#   destination
#   nginx_name
#
#######################################
function s1_cleanup() {
  send "rm -r ${destination}"
  send "mkdir ${destination}"
  send "rm /etc/nginx/sites-enabled/${nginx_name}"
}

#######################################
# Clone repositories to /var/www/deploy
# Globals:
#   client_destination
#   client_repository
#   server_destination
#   server_repository
#
#######################################
function s2_clone() {
  clone "${server_repository}" ${server_destination}
  clone "${client_repository}" ${client_destination}
  copy ~/.env/.env.client ${client_destination}/.env
}

#######################################
# Install dependencies & bundle for production both application
#######################################
function s3_build_all() {
  npm_common "install"
  npm_common "run-script build"
}

#######################################
# Copy environment & service files for server
# Globals:
#   server_destination
#   server_name
#
#######################################
function s4_copy_server_environment() {
  copy ~/.env/.env.server ${server_destination}/dist/.env

  cat << EOF > ${server_name}.service
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
  copy "$(get ${server_name}.service)" ${service_destination}

}

#######################################
# Give permissions to correct users
# Globals:
#   client_destination
#   server_destination
#
#######################################
function s5_assign_permissions() {
  send "chown www-data -R ${client_destination}"
  send "chown nanstis -R ${server_destination}"
  send "chmod +x ${server_destination}/dist/index.js"
}

#######################################
# Enable nginx reverse-proxy
# Globals:
#   nginx_destination
#   nginx_name
#
#######################################
function s6_enable_proxy() {
  copy "$(get nanstis.nginx)" ${nginx_destination}/${nginx_name}
  send "ln -s ${nginx_destination}/${nginx_name} /etc/nginx/sites-enabled"
}

#######################################
# Reload systemd daemon & services
# Globals:
#   server_name
#
#######################################
function s7_reload_systemd() {
  send "systemctl daemon-reload"
  send "systemctl enable ${server_name}"
  send "systemctl start ${server_name}"
  send "systemctl restart nginx"
}

#######################################
# Deploy to nanstis.ch
# Globals:
#   client_name
#   server_name
#   destination
#   server_destination
#   client_destination
#   host
#
#######################################
function main() {
  base_path=$(realpath --relative-to="$(pwd)" /opt/bash/)

  server_repository="https://github.com/nanstis/nanstis-server.git"
  client_repository="https://github.com/nanstis/nanstis-client.git"

  local client_name="n-client"
  server_name="n-server"
  nginx_name="nanstis"

  destination="/var/www/deploy"
  service_destination="/etc/systemd/system"
  nginx_destination="/etc/nginx/sites-available"

  host=root@nanstis.ch
  server_destination=${destination}/${server_name}
  client_destination=${destination}/${client_name}

  s1_cleanup
  s2_clone
  s3_build_all
  s4_copy_server_environment
  s5_assign_permissions
  s6_enable_proxy
  s7_reload_systemd

}

main "$@"
