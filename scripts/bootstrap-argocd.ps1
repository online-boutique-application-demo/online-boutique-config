[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$Env,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Resolve directories
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$AppsDir = Join-Path $RepoRoot "argocd\apps\$Env"

if (-not (Test-Path $AppsDir)) {
    Write-Error "Environment directory does not exist: $AppsDir"
    exit 1
}

# Validate required environment variables
$GithubOrg = $env:GITHUB_ORG
$AwsAccountId = $env:AWS_ACCOUNT_ID
$AwsRegion = $env:AWS_REGION

if ([string]::IsNullOrWhiteSpace($GithubOrg)) {
    Write-Error "Required environment variable GITHUB_ORG is not set or empty"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($AwsAccountId)) {
    Write-Error "Required environment variable AWS_ACCOUNT_ID is not set or empty"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($AwsRegion)) {
    Write-Error "Required environment variable AWS_REGION is not set or empty"
    exit 1
}

# Set defaults
$ClusterName = if ($env:EKS_CLUSTER_NAME) { $env:EKS_CLUSTER_NAME } else { "online-boutique-$Env" }
$ConfigRevision = if ($env:CONFIG_REVISION) { $env:CONFIG_REVISION } else { "deploy/$Env" }

# Handle Grafana admin password
$GrafanaPassword = $env:GRAFANA_ADMIN_PASSWORD
if ([string]::IsNullOrWhiteSpace($GrafanaPassword)) {
    if ([Environment]::UserInteractive) {
        $secPass = Read-Host -Prompt "Enter Grafana Admin Password" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
        $GrafanaPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    } else {
        Write-Error "Required environment variable GRAFANA_ADMIN_PASSWORD is not set in non-interactive mode"
        exit 1
    }
}

if ([string]::IsNullOrWhiteSpace($GrafanaPassword)) {
    Write-Error "GRAFANA_ADMIN_PASSWORD cannot be empty"
    exit 1
}

# Namespace & Secret logic
if ($DryRun) {
    Write-Output "# --- Namespace: monitoring ---"
    kubectl create namespace monitoring --dry-run=client -o yaml
    Write-Output "---"
    Write-Output "# --- Secret: grafana-admin ---"
    kubectl create secret generic grafana-admin --namespace monitoring --from-literal="admin-user=admin" --from-literal="admin-password=REDACTED" --dry-run=client -o yaml
} else {
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic grafana-admin --namespace monitoring --from-literal="admin-user=admin" --from-literal="admin-password=$GrafanaPassword" --dry-run=client -o yaml | kubectl apply -f -
}

# Render and apply manifests
$files = Get-ChildItem -Path $AppsDir -Filter "*.yaml" | Sort-Object Name
foreach ($file in $files) {
    $content = Get-Content -Raw -Path $file.FullName
    $rendered = $content.Replace('${GITHUB_ORG}', $GithubOrg).
                         Replace('${AWS_ACCOUNT_ID}', $AwsAccountId).
                         Replace('${AWS_REGION}', $AwsRegion).
                         Replace('${EKS_CLUSTER_NAME}', $ClusterName).
                         Replace('${CONFIG_REVISION}', $ConfigRevision)

    if ($DryRun) {
        Write-Output "---"
        Write-Output "# --- Rendered from $($file.Name) ---"
        Write-Output $rendered
    } else {
        $rendered | kubectl apply -f -
    }
}
