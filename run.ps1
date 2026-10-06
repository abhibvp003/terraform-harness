<#
.SYNOPSIS
    PowerShell equivalent of run.sh, for Windows without Git Bash or WSL.

.DESCRIPTION
    .\run.ps1 <command> [env]

    env defaults to "dev" and must match a file in envs\<env>.tfvars.

    If terraform is not on PATH, set $env:TERRAFORM_BIN first:
        $env:TERRAFORM_BIN = "C:\tools\terraform.exe"

.EXAMPLE
    .\run.ps1 check
    .\run.ps1 plan dev
    .\run.ps1 apply dev
    .\run.ps1 destroy dev
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$Environment = 'dev'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir = $PSScriptRoot
$EnvsDir = Join-Path $ScriptDir 'envs'
$Terraform = if ($env:TERRAFORM_BIN) { $env:TERRAFORM_BIN } else { 'terraform' }

function Write-Info { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Blue }
function Write-Ok { param([string]$Message) Write-Host "[ok] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[warn] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[error] $Message" -ForegroundColor Red; exit 1 }

function Show-Usage {
    @'
Usage: .\run.ps1 <command> [env]

Commands:
  init          Initialise Terraform and download providers
  fmt           Rewrite all .tf files to canonical format
  validate      Check formatting and configuration validity
  plan          Show what would change, saved to tfplan.<env>
  apply         Apply the saved plan (runs plan first, then asks)
  destroy       Tear everything down (asks first)
  kubeconfig    Point kubectl at the cluster
  status        Show nodes and all pods
  output        Print Terraform outputs
  cost          Print the cost breakdown for this setup
  check         Preflight: tools, credentials, account

Environments:
  Any envs\<name>.tfvars. Defaults to "dev".

Examples:
  .\run.ps1 check
  .\run.ps1 plan dev
  .\run.ps1 apply dev
  .\run.ps1 destroy dev
'@ | Write-Host
}

function Test-Tool {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Assert-Terraform {
    if (-not (Test-Tool $Terraform)) {
        Write-Err @"
terraform not found.

Install it, or point at the binary:
  `$env:TERRAFORM_BIN = "C:\path\to\terraform.exe"

Downloads: https://developer.hashicorp.com/terraform/install
"@
    }
}

function Resolve-Env {
    param([string]$Name)

    # Reject anything that is not a plain name so it cannot be smuggled into
    # a path.
    if ($Name -notmatch '^[a-z0-9][a-z0-9-]*$') {
        Write-Err "Invalid environment name: '$Name'. Use lowercase letters, digits and hyphens."
    }

    $file = Join-Path $EnvsDir "$Name.tfvars"
    if (-not (Test-Path -LiteralPath $file)) {
        Write-Host "No such environment: $Name`n`nAvailable:" -ForegroundColor Red
        Get-ChildItem -Path $EnvsDir -Filter '*.tfvars' -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "  $($_.BaseName)" }
        exit 1
    }

    return $Name
}

function Confirm-Action {
    param([string]$Prompt, [string]$Expected)

    if ($env:FORCE -eq '1') {
        Write-Warn 'FORCE=1 set, skipping confirmation'
        return
    }

    Write-Host ''
    Write-Host $Prompt -ForegroundColor White
    $answer = Read-Host "Type '$Expected' to continue"

    if ($answer -ne $Expected) {
        Write-Info 'Aborted.'
        exit 1
    }
}

function Invoke-Terraform {
    param([string[]]$Arguments)

    & $Terraform @Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Err "terraform $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

function Invoke-Check {
    $failed = $false

    Write-Info 'Checking tools'
    foreach ($tool in @($Terraform, 'aws', 'kubectl')) {
        if (Test-Tool $tool) {
            Write-Ok $tool
        }
        else {
            Write-Warn "$tool not found"
            if ($tool -ne 'kubectl') { $failed = $true }
        }
    }

    Write-Info 'Checking AWS credentials'
    if (-not (Test-Tool 'aws')) {
        Write-Warn 'skipped, aws CLI missing'
    }
    else {
        $account = & aws sts get-caller-identity --query Account --output text 2>$null
        if ($LASTEXITCODE -eq 0 -and $account) {
            Write-Ok "account $account"
            $arn = & aws sts get-caller-identity --query Arn --output text
            Write-Ok "identity $arn"
            Write-Host ''
            Write-Host '  Add this to envs\<env>.tfvars so you can use kubectl:'
            Write-Host "    cluster_admin_principal_arns = [`"$arn`"]"
            Write-Host ''
        }
        else {
            Write-Warn 'no valid AWS credentials. Run: aws configure'
            $failed = $true
        }
    }

    if ($failed) { Write-Err 'Preflight failed.' }
    Write-Ok 'Ready.'
}

function Invoke-Init {
    Assert-Terraform
    Write-Info 'Initialising'
    Invoke-Terraform @("-chdir=$ScriptDir", 'init', '-input=false')
    Write-Ok 'Initialised.'
}

function Invoke-Fmt {
    Assert-Terraform
    Write-Info 'Formatting'
    Invoke-Terraform @("-chdir=$ScriptDir", 'fmt', '-recursive')
    Write-Ok 'Formatted.'
}

function Invoke-Validate {
    Assert-Terraform

    Write-Info 'Checking formatting'
    & $Terraform "-chdir=$ScriptDir" fmt -recursive -check
    if ($LASTEXITCODE -ne 0) { Write-Err 'Formatting issues. Run: .\run.ps1 fmt' }
    Write-Ok 'Formatting clean.'

    Write-Info 'Validating configuration'
    Invoke-Terraform @("-chdir=$ScriptDir", 'validate')
    Write-Ok 'Configuration valid.'
}

function Invoke-Plan {
    param([string]$EnvName)

    Assert-Terraform
    Write-Info "Planning '$EnvName'"
    Invoke-Terraform @(
        "-chdir=$ScriptDir", 'plan', '-input=false',
        "-var-file=envs/$EnvName.tfvars",
        "-out=tfplan.$EnvName"
    )
    Write-Ok "Plan saved to tfplan.$EnvName"
}

function Invoke-Apply {
    param([string]$EnvName)

    Invoke-Plan $EnvName

    @"

This creates billable AWS resources.

  EKS control plane   ~0.10/hour  (~73/month) - no free tier
  Worker node(s)      ~0.04/hour  per t3.medium

  Roughly 0.15/hour, about 109/month if left running.

  Tear it down when you are done: .\run.ps1 destroy $EnvName
"@ | Write-Host

    Confirm-Action "Apply the plan above to environment '$EnvName'?" 'yes'

    Write-Info "Applying '$EnvName' (10-15 minutes)"
    Invoke-Terraform @("-chdir=$ScriptDir", 'apply', '-input=false', "tfplan.$EnvName")

    Remove-Item -LiteralPath (Join-Path $ScriptDir "tfplan.$EnvName") -ErrorAction SilentlyContinue
    Write-Ok 'Applied.'

    Write-Host ''
    Write-Host 'Next:'
    Write-Host "  .\run.ps1 kubeconfig $EnvName"
    Write-Host "  .\run.ps1 status $EnvName"
    Write-Host ''
}

function Invoke-Destroy {
    param([string]$EnvName)

    Assert-Terraform

    Write-Info "Planning destroy for '$EnvName'"
    Invoke-Terraform @(
        "-chdir=$ScriptDir", 'plan', '-destroy', '-input=false',
        "-var-file=envs/$EnvName.tfvars"
    )

    Confirm-Action "Destroy EVERYTHING in '$EnvName'? This cannot be undone." "destroy $EnvName"

    Write-Info "Destroying '$EnvName'"
    Invoke-Terraform @(
        "-chdir=$ScriptDir", 'destroy', '-input=false', '-auto-approve',
        "-var-file=envs/$EnvName.tfvars"
    )

    Write-Ok 'Destroyed. Billing has stopped.'
}

function Invoke-Kubeconfig {
    param([string]$EnvName)

    Assert-Terraform
    if (-not (Test-Tool 'aws')) { Write-Err 'aws CLI not found.' }

    $cluster = & $Terraform "-chdir=$ScriptDir" output -raw cluster_name 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $cluster) {
        Write-Err "No cluster in state. Run: .\run.ps1 apply $EnvName"
    }

    $region = & $Terraform "-chdir=$ScriptDir" output -raw region 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $region) { $region = 'us-east-1' }

    Write-Info "Writing kubeconfig for $cluster"
    & aws eks update-kubeconfig --region $region --name $cluster
    Write-Ok "kubectl now targets $cluster"

    @'

If kubectl times out, the API endpoint is private (the default). Either:
  - run kubectl from inside the VPC, or
  - set cluster_endpoint_public_access = true plus
    cluster_endpoint_public_access_cidrs = ["YOUR.IP/32"] and re-apply
'@ | Write-Host
}

function Invoke-Status {
    if (-not (Test-Tool 'kubectl')) { Write-Err 'kubectl not found.' }
    Write-Info 'Nodes'
    & kubectl get nodes -o wide
    Write-Host ''
    Write-Info 'Pods'
    & kubectl get pods --all-namespaces
}

function Invoke-Output {
    Assert-Terraform
    Invoke-Terraform @("-chdir=$ScriptDir", 'output')
}

function Invoke-Cost {
    @'
Monthly cost, us-east-1, running 24/7 with envs\dev.tfvars
----------------------------------------------------------

  EKS control plane            73.00    no free tier, unavoidable
  1 x t3.medium on-demand      30.37    free tier covers t3.micro only
  1 x public IPv4               3.65    replaces a ~33/month NAT gateway
  30 GB gp3 root volume         2.40    free tier covers 30 GB for 12 months
  CloudWatch logs (audit)       ~0.50   within the 5 GB free tier
                             --------
  TOTAL                       ~109/month
  HOURLY                        ~0.15

Already switched off in envs\dev.tfvars
---------------------------------------

  NAT gateway        -33.00/month   nodes use public subnets instead
  VPC endpoints     -146.00/month   10 endpoints x 2 AZs x 0.01/hour
  VPC flow logs        -0.50/GB     nothing depends on them
  3 KMS CMKs          -3.00/month   AWS-managed keys still encrypt at rest

What is NOT in the AWS free tier
--------------------------------

  The EKS control plane has no free tier at any usage level. Two thirds of
  the bill above is the control plane, and no configuration change reduces it.

  The free tier EC2 allowance is 750 hours/month of t3.micro. A t3.micro
  caps at 4 pods and cannot fit kube-system, so it will not run a cluster.

The only real lever
-------------------

  Destroy between sessions. At ~0.15/hour:

    3 hour session      ~0.45
    8 hour day          ~1.20
    left running 1 week ~25.00

    .\run.ps1 apply dev      before you start
    .\run.ps1 destroy dev    when you finish

  Set a billing alarm as well:
    https://console.aws.amazon.com/billing/home#/budgets
'@ | Write-Host
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

if (-not $Command) { Show-Usage; exit 1 }

switch ($Command.ToLower()) {
    'check' { Invoke-Check }
    'init' { Invoke-Init }
    'fmt' { Invoke-Fmt }
    'validate' { Invoke-Validate }
    'cost' { Invoke-Cost }
    'output' { Invoke-Output }
    'status' { Invoke-Status }
    'plan' { Invoke-Plan (Resolve-Env $Environment) }
    'apply' { Invoke-Apply (Resolve-Env $Environment) }
    'destroy' { Invoke-Destroy (Resolve-Env $Environment) }
    'kubeconfig' { Invoke-Kubeconfig (Resolve-Env $Environment) }
    { $_ -in 'help', '-h', '--help' } { Show-Usage }
    default {
        Write-Host "Unknown command: $Command`n" -ForegroundColor Red
        Show-Usage
        exit 1
    }
}
