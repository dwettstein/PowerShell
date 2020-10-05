<#
.SYNOPSIS
    Remove an account from a CyberArk server.

.DESCRIPTION
    Remove an account from a CyberArk server.

    Also have a look at https://github.com/pspete/psPAS for more functionality.

    CyberArk API documentation can be found here: https://docs.cyberark.com/

    File-Name:  Remove-CyberArkAccount.ps1
    Author:     David Wettstein
    Version:    v1.0.2

    Changelog:
                v1.0.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2020-03-16, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.LINK
    https://github.com/pspete/psPAS

.LINK
    https://docs.cyberark.com/

.EXAMPLE
    $Result = & "Remove-CyberArkAccount" $Account -Server "example.com"

.EXAMPLE
    $Result = & "$PSScriptRoot\Remove-CyberArkAccount" -Account $Account -AsJson

.EXAMPLE
    & "$PSScriptRoot\Get-CyberArkAccount" "query params" | & "$PSScriptRoot\Remove-CyberArkAccount"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    $Account  # Account ID or output from Get-CyberArkAccount
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Alias("Insecure")]
    [Switch] $ApproveAllCertificates
)

if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

#===============================================================================
# Initialization and Functions
#===============================================================================
# Make sure the necessary modules are loaded.
$Modules = @()
$LoadedModules = Get-Module; $Modules | ForEach-Object {
    if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
}

$StartDate = [DateTime]::Now

[String] $FILE_NAME = $MyInvocation.MyCommand.Name
if ($PSVersionTable.PSVersion.Major -lt 3 -or [String]::IsNullOrEmpty($PSScriptRoot)) {
    # Join-Path with empty child path is used to append a path separator.
    [String] $FILE_DIR = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) ""
} else {
    [String] $FILE_DIR = Join-Path $PSScriptRoot ""
}
if ($MyInvocation.MyCommand.Module) {
    $FILE_DIR = ""  # If this script is part of a module, we want to call module functions not files.
}

$ExitCode = 0
$ErrorOut = ""
$ScriptOut = ""

Write-Verbose "$($FILE_NAME): CALL."

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    if ($Account.GetType() -eq [String]) {
        $AccountId = $Account
    } else {
        $AccountId = $Account.id
    }
    $Endpoint = "/PasswordVault/api/Accounts/$AccountId"
    if ($ApproveAllCertificates) {
        $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "DELETE" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates
    } else {
        $Response = & "${FILE_DIR}Invoke-CyberArkRequest" -Server $Server -Method "DELETE" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken
    }
    if ($Response.StatusCode -lt 200 -or $Response.StatusCode -ge 300) {
        throw "Failed to invoke $($Endpoint): $($Response.StatusCode) - $($Response.Content)"
    }
    Write-Verbose "Account $AccountId successfully deleted: $($Response.StatusCode)"
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction Continue
    $Ex = $_.Exception
    if ($Ex.InnerException) { $Ex = $Ex.InnerException }
    $ErrorOut = "$($Ex.Message)"
    $ExitCode = 1
} finally {
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ([DateTime]::Now - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        $ScriptOut  # Write ScriptOut to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}
