#!/bin/bash
## This tool will try to detect common cli tools and will configure the Netskope SSL certificate bundle.
## Original Code by Dudu Akiva @ Netskope
## Updated version: Kostya Maryan @ Bulwarx Ltd.
## Date: 18/08/2024

# To add a new tool, use the `configure_tool` function with the appropriate parameters.
# Example:
# configure_tool "Tool Name" "ENV_VAR_NAME" "check_command" "post_command"
# - tool_name: The name of the tool (for display purposes)
# - env_var: The environment variable to set (if applicable)
# - check_command: The command to check if the tool is installed (usually the tool's executable name)
# - post_command: Any additional configuration command needed after setting the environment variable (can be empty if not needed)
#
# Example for adding a hypothetical tool "MyTool":
# configure_tool "MyTool" "MYTOOL_CA_CERTS" "mytool" "mytool config set cafile $cert_dir/$cert_name"

##############
## PARAMS ####
##############
# These parameters are optional. If they are not set the script runs in manual mode and asks
# and request for a user prompt to proceed.
tenant_name=""
cert_name=""
cert_dir=""
org_key=""
recreate_cert=false

debug_mode=false

###############
## FUNCTIONS ##
###############

log() {
    current_time=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$current_time] $1"
}

# Check which shell environment is used (zsh or bash)
get_shell(){
    my_shell=$(echo $SHELL)
    log "Shell used is [$my_shell]"
    if [[ $my_shell == *"bash"* ]]; then
        shell=~/.bash_profile
    else
        shell=~/.zshenv
    fi
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to create or update certificate bundle
create_cert_bundle() {
  log "Creating cert bundle:"
  # Original script values
  curl -k "https://addon-$tenant_name/config/ca/cert?orgkey=$org_key" > $cert_dir/$cert_name
  curl -k "https://addon-$tenant_name/config/org/cert?orgkey=$org_key" >> $cert_dir/$cert_name
  curl -k -L "https://ccadb-public.secure.force.com/mozilla/IncludedRootsPEMTxt?TrustBitsInclude=Websites" >> $cert_dir/$cert_name
}

# Function to configure a tool with the certificate bundle
configure_tool() {
  local tool_name=$1
  local env_var=$2
  local check_command=$3
  local post_command=$4

  log "[$tool_name] checking if tool is installed"
  if command_exists $check_command; then
    log "[$tool_name] tool is installed"
    if [ "$debug_mode" = true ] ; then
      $check_command --version
    fi

    if [[ -n "$env_var" ]]; then
      if [[ ${!env_var} == "$cert_dir/$cert_name" ]]; then
        log "[$tool_name] already configured, skipping .."
      else
        log "[$tool_name] Configuring tool"
        echo "export $env_var=\"$cert_dir/$cert_name\"" >> $shell
        source $shell
        #echo "$env_var="$cert_dir/$cert_name""
        #export $env_var="$cert_dir/$cert_name"
        #echo "export $env_var=\"$cert_dir/$cert_name\"" >> configured_tools.sh
      fi
    fi
    
    if [[ -n "$post_command" ]]; then
      log "[$tool_name] Running post command: [$post_command]"
      eval $post_command
      #echo "$post_command" >> configured_tools.sh
    fi
  else
    log "[$tool_name] is not installed"
  fi
}


##############
## MAIN ######
##############
current_time=$(date "+%Y-%m-%d %H:%M:%S")

echo "################################################################"
echo " Starting a new Netskope SSL Cert instance ($current_time) "
echo "################################################################"
echo
echo "Script parameters:"
echo -e "tenant_name: \t [$tenant_name]"
echo -e "org_key: \t [$org_key]"
echo -e "cert_name: \t [$cert_name]"
echo -e "cert_dir: \t [$cert_dir]"
echo -e "recreate_cert: \t [$recreate_cert]"
echo

# Get shell config
log "Getting shell configuration"
get_shell

# Get tenant information to create certificate bundle
if [ -z "$tenant_name" ] ; then
  log "tenant_name not provided."
  read -p "Please provide full tenant name (ex: mytenant.eu.goskope.com): " tenant_name
else
  log "Using configured tenant_name"
fi

if [ -z "$tenant_name" ] ; then
  log "org_key not provided."
  read -p "Please provide tenant org_key: " org_key
else
  log "Using configured org_key"
fi

log "Testing if tenant [$tenant_name] is reachable"
status_code=$(curl -k --write-out %{http_code} --silent --output /dev/null https://$tenant_name/locallogin)
if [[ "$status_code" -ne "307" ]] ; then
  log "ERROR: Tenant Unreachable"
  exit 1
else
  log "Tenant Reachable"
fi

#read -p "Please provide certificate bundle name [netskope-cert-bundle.pem]: " cert_name
log "Using configured cert_name"
cert_name=${cert_name:-netskope-cert-bundle.pem}

if [ -z "$cert_dir" ] ; then
  read -p "Please provide certficate bundle location [~/netskope]: " cert_dir
  cert_dir=${cert_dir:-~/netskope}
else
  log "Using configured cert_dir"
fi

if [ ! -d "$cert_dir" ] ; then
  log "[$cert_dir] directory does not exist."
  log "creating directory [$cert_dir]"
  mkdir -p $cert_dir
fi

# Set Certificate bundle name and location
if [ -f "$cert_dir/$cert_name" ] ; then
  log "[$cert_name] already exists in [$cert_dir]"
  
  if [ "$recreate_cert" = false ] ; then
    read -p "Recreate Certificate Bundle? (y/N) " -n 1 -r
    echo    
    if [[ $REPLY =~ ^[Yy]$ ]] ; then
      create_cert_bundle
    fi
  else
    log "Cert bundle already exists but certificate recreate set to [true]"
    create_cert_bundle
  fi
else
  create_cert_bundle
fi

# This allows for later silent runs on other machines
#> configured_tools.sh

# Configure tools
configure_tool "Git" "GIT_SSL_CAPATH" "git" ""
configure_tool "OpenSSL" "SSL_CERT_FILE" "openssl" ""
configure_tool "cURL" "SSL_CERT_FILE" "curl" ""
configure_tool "Python Requests Library" "REQUESTS_CA_BUNDLE" "" ""
configure_tool "AWS CLI" "AWS_CA_BUNDLE" "awscli" ""
configure_tool "Google Cloud CLI" "" "gcloud" "gcloud config set core/custom_ca_certs_file $cert_dir/$cert_name"
configure_tool "NodeJS Package Manager (NPM)" "" "npm" "npm config set cafile $cert_dir/$cert_name"
configure_tool "NodeJS" "NODE_EXTRA_CA_CERTS" "node" ""
configure_tool "Ruby" "SSL_CERT_FILE" "ruby" ""
configure_tool "PHP Composer" "" "composer" "composer config --global cafile $cert_dir/$cert_name"
configure_tool "GoLang" "SSL_CERT_FILE" "go" ""
configure_tool "Azure CLI" "REQUESTS_CA_BUNDLE" "az" ""
configure_tool "Python PIP" "REQUESTS_CA_BUNDLE" "pip3" ""
configure_tool "Oracle Cloud CLI" "REQUESTS_CA_BUNDLE" "oci-cli" ""
configure_tool "Cargo Package Manager" "SSL_CERT_FILE" "cargo" ""
configure_tool "Yarn" "" "yarnpkg" "yarnpkg config set httpsCaFilePath $cert_dir/$cert_name"

# Check if Azure Storage Explorer exists
if [ -d ~/Library/Application\ Support/StorageExplorer/certs ]; then
  log "Azure Storage Explorer is installed"
  cp "$cert_dir/$cert_name" ~/Library/Application\ Support/StorageExplorer/certs
  log "Azure Storage Explorer configured"
  log "cp \"$cert_dir/$cert_name\" ~/Library/Application\ Support/StorageExplorer/certs" >> configured_tools.sh
else
  log "Azure Storage Explorer is not installed"
fi

echo
echo "################################################################"
echo " Netskope SSL Cert instance finished successfully ($current_time) "
echo "################################################################"