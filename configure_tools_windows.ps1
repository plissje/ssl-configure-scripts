## This tool will try to detect common cli tools and will configure the Netskope SSL certificate bundle.
## Original Code by Dudu Akiva @ Netskope
## Updated version: Kostya Maryan @ Bulwarx Ltd.
## Date: 29/08/2024



##############
## PARAMS ####
##############
# These parameters are optional. If they are not set the script runs in manual mode and asks
# and request for a user prompt to proceed.
$tenant_name = ""
$cert_name = "netskope-cert-bundle.pem"
$cert_dir = "C:\Netskope"
$org_key = ""
$recreate_cert = $true


function Write-Log {
    param(
        [string]$message
    )
    $current_time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$current_time] $message"
}

function Test-CommandExists {
    param ($command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'
    try {
        if (Get-Command $command) { 
            $cmdType = (Get-Command $command).CommandType
            if ($cmdType -eq "Alias") { return $false }
            else { return $true }
        }
    } catch { return $false }
    finally { $ErrorActionPreference = $oldPreference }
}

function Invoke-ConfigureTool {
    param(
        $toolName,
        $versionCmd,
        $getConfigCmd,
        $setConfigCmd
    )
    
    Write-Log "[$toolName] is installed"
    Invoke-Expression $versionCmd
    
    $currentConfig = Invoke-Expression $getConfigCmd
    if ($currentConfig -eq "$cert_dir\$cert_name") {
        Write-Log "[$toolName] Already configured"
    } else {
        Invoke-Expression $setConfigCmd
        Write-Log "[$toolName] Configured"
    }
}


##############
#### MAIN ####
##############
$current_time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "################################################################"
Write-Host " Starting a new Netskope SSL Cert instance ($current_time) "
Write-Host "################################################################"
Write-Host
Write-Log "Script parameters:"
Write-Log "tenant_name: `t [$tenant_name]"
Write-Log "org_key: `t`t [$org_key]"
Write-Log "cert_name: `t [$cert_name]"
Write-Log "cert_dir: `t [$cert_dir]"
Write-Log "recreate_cert: `t [$recreate_cert]"
Write-Log

# Get tenant information to create certificate bundle
if ([string]::IsNullOrEmpty($tenant_name)) {
    $tenant_name = Read-Host "Please provide full tenant name (ex: mytenant.eu.goskope.com)"
} else { Write-Log "Using configured tenant_name"}

if ([string]::IsNullOrEmpty($org_key)) {
    $org_key = Read-Host "Please provide tenant orgkey"
} else { Write-Log "Using configured org_key"}

# Set Certificate bundle name and location
if ([string]::IsNullOrEmpty($cert_name)) {
    $cert_name = Read-Host "Please provide certificate bundle name [netskope-cert-bundle.pem]"
    if ([string]::IsNullOrEmpty($cert_name)) { $cert_name = "netskope-cert-bundle.pem" }
} else { Write-Log "Using configured cert_name"}

if ([string]::IsNullOrEmpty($cert_dir)) {
    $cert_dir = Read-Host "Please provide certificate bundle location [C:\netskope]"
    if ([string]::IsNullOrEmpty($cert_dir)) { $cert_dir = "C:\netskope" }
} Else { Write-Log "Using configured cert_dir"}

if (-not (Test-Path $cert_dir)) {
    Write-Log "[$cert_dir] does not exist, creating it .."
    New-Item -ItemType Directory -Path $cert_dir | Out-Null
}

# Check tenant reachability
$statusCode = (Invoke-WebRequest -Uri "https://$tenant_name/locallogin" -ErrorAction SilentlyContinue).StatusCode 
if ( $statusCode -eq 200 -or $statusCode -eq 307 -or $statusCode -eq 302 ) {
    Write-Log "Tenant Reachable"
} else {
    Write-Log "[ERROR] Tenant Unreachable"
    exit 1
}

# Create or update certificate bundle
$certBundleExists = Test-Path "$cert_dir\$cert_name"
if ($certBundleExists) {
    Write-Log "[$cert_name] already exists in [$cert_dir]."
    
    if ( $recreate_cert -eq $false ) {
        $recreate = Read-Host "Recreate Certificate Bundle? (y/n)"
        $certBundleExists = $recreate -ne "y"
    }
}

if ( (-not $certBundleExists) -or $recreate_cert -eq $true ) {
    $fileRootCA = "$cert_dir\$cert_name.rootca"
    $fileSubCA  = "$cert_dir\$cert_name.subca"
    $fileGlobal = "$cert_dir\$cert_name.globalcas"

    Write-Log "Creating cert bundle"
    Invoke-WebRequest -Uri "https://addon-$tenant_name/config/ca/cert?orgkey=$org_key" -OutFile $fileRootCA
    Invoke-WebRequest -Uri "https://addon-$tenant_name/config/org/cert?orgkey=$org_key" -OutFile $fileSubCA
    Invoke-WebRequest -Uri "https://ccadb-public.secure.force.com/mozilla/IncludedRootsPEMTxt?TrustBitsInclude=Websites" -OutFile $fileGlobal
    
    Get-Content $fileRootCA, $fileSubCA, $fileGlobal | Out-File -FilePath "$cert_dir\$cert_name" -Encoding utf8
    Get-Content $fileSubCA, $fileRootCA | Out-File -FilePath "$cert_dir\netskope_only.pem" -Encoding utf8
    $filesToDelete = @($fileRootCA, $fileSubCA, $fileGlobal) 
    Remove-Item -Path $filesToDelete
}

# Tools configuration (add more tools here as needed)
# Git
$tool_name = "Git"
Write-Log "[$tool_name] checking if tool is installed"
if (Test-CommandExists "git") {
    Write-log "[$tool_name] Configuring tool"
    Invoke-ConfigureTool "$tool_name" "git --version" "git config --global http.sslCAInfo" "git config --global http.sslCAInfo `"$cert_dir\$cert_name`""
}

# OpenSSL
$tool_name = "OpenSSL"
Write-Log "[$tool_name] checking if tool is installed"
if (Test-CommandExists "openssl") {
    Write-log "[$tool_name] Configuring tool"
    Invoke-ConfigureTool "$tool_name" "openssl version -a" "[Environment]::GetEnvironmentVariable('SSL_CERT_FILE', 'User')" "[Environment]::SetEnvironmentVariable('SSL_CERT_FILE', '$cert_dir\$cert_name', 'User')"
}

# Curl
$tool_name = "cURL"
Write-Log "[$tool_name] checking if tool is installed"
if (Test-CommandExists "curl") {
    Write-log "[$tool_name] Configuring tool"
    Invoke-ConfigureTool "$tool_name" "curl --version" "[Environment]::GetEnvironmentVariable('SSL_CERT_FILE', 'User')" "[Environment]::SetEnvironmentVariable('SSL_CERT_FILE', '$cert_dir\$cert_name', 'User')"
}

# AWS CLI
$tool_name = "cURL"
Write-Log "[$tool_name] checking if tool is installed"
if (Test-CommandExists "aws") {
    Write-log "[$tool_name] Configuring tool"
    Invoke-ConfigureTool "$tool_name" "aws --version" "[Environment]::GetEnvironmentVariable('AWS_CA_BUNDLE', 'User')" "[Environment]::SetEnvironmentVariable('AWS_CA_BUNDLE', '$cert_dir\$cert_name', 'User')"
}

# Node JS
$tool_name = "Node JS Extra Certs"
Write-log "[$tool_name] Configuring tool"
[Environment]::SetEnvironmentVariable('NODE_EXTRA_CA_CERTS', "$cert_dir\$cert_name", 'User')

# Python Requests
$tool_name = "Python Requests"
Write-Log "[$tool_name] checking if tool is installed"
$pythonRequestsBundle = [Environment]::GetEnvironmentVariable('REQUESTS_CA_BUNDLE', 'User')
if ($pythonRequestsBundle -eq "$cert_dir\$cert_name") {
    Write-log "[$tool_name] Tool already configured, skipping .."
} else {
    [Environment]::SetEnvironmentVariable('REQUESTS_CA_BUNDLE', "$cert_dir\$cert_name", 'User')
    Write-Log "[$tool_name] Tool configured"
}

# Google Cloud CLI
$tool_name = "Google Cloud CLI"
Write-Log "[$tool_name] Checking if tool is installed"
if (Test-CommandExists "gcloud") {
    Write-Log "[$tool_name] Tool is installed"
    gcloud --version
    gcloud config set core/custom_ca_certs_file "$cert_dir\$cert_name"
    Write-Log "[$tool_name] Tool configured"
} else {
    Write-Log "[$tool_name] Tool is not installed"
}

# ... Continue with other tools (npm, node, ruby, composer, go, az, pip, oci, cargo, yarn) ...
# The pattern would be similar to the examples above, adjusting for each tool's specific commands and environment variables.

Write-Host
Write-Host "################################################################"
Write-Host " Netskope SSL Cert instance finished successfully ($current_time) "
Write-Host "################################################################"