<#
.SYNOPSIS
    Wait until a task of a vCloud server has been completed (either successfully or not).

.DESCRIPTION
    Wait until a task of a vCloud server has been completed (either successfully or not).

    File-Name:  Wait-VCloudTask.ps1
    Author:     David Wettstein
    Version:    v1.0.2

    Changelog:
                v1.0.2, 2020-05-07, David Wettstein: Reorganize input params.
                v1.0.1, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory=$true, ValueFromPipeline = $true, Position=0)]
    [ValidatePattern('.*[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}.*')]
    [String] $Task
    ,
    [Parameter(Mandatory=$false, Position=1)]
    [Int] $SleepInSec = 5
    ,
    [Parameter(Mandatory=$false, Position=2)]
    [Int] $TimeoutInSec = 3600  # 60min
    ,
    [Parameter(Mandatory=$false, Position=3)]
    [String] $Server
    ,
    [Parameter(Mandatory=$false, Position=4)]
    [String] $AuthorizationToken = $null
    ,
    [Parameter(Mandatory=$false, Position=5)]
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

$StatusRunning = @('queued', 'preRunning', 'running')
$StatusCompleted = @('success', 'error', 'canceled', 'aborted')

try {
    $TaskId = & "${FILE_DIR}Split-VCloudId" -UrnOrHref $Task
    do {
        $CurrentDate = [DateTime]::Now
        if ($TimeoutInSec -and ($CurrentDate -gt $StartDate.AddSeconds($TimeoutInSec))) {
            throw "Timeout while waiting for task '$Task' to complete, current status is '$TaskStatus'."
        }
        $null = Start-Sleep -Seconds $SleepInSec

        $Endpoint = "/api/task/$TaskId"
        if ($ApproveAllCertificates) {
            [Xml] $Response = & "${FILE_DIR}Invoke-VCloudRequest" -Server $Server -Method "GET" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken -ApproveAllCertificates
        } else {
            [Xml] $Response = & "${FILE_DIR}Invoke-VCloudRequest" -Server $Server -Method "GET" -Endpoint $Endpoint -AuthorizationToken $AuthorizationToken
        }
        $TaskStatus = $Response.Task.status
    } while ($TaskStatus -in $StatusRunning)
    $ScriptOut = $TaskResponse.Task
} catch {
    # Error in $_ or $Error[0] variable.
    Write-Warning "Exception occurred at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.ToString())" -WarningAction Continue
    $ErrorOut = "$($_.Exception.Message)"
    $ExitCode = 1
} finally {
    $EndDate = [DateTime]::Now
    Write-Verbose ("$($FILE_NAME): ExitCode: {0}. Execution time: {1} ms. Started: {2}." -f $ExitCode, ($EndDate - $StartDate).TotalMilliseconds, $StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))

    if ($ExitCode -eq 0) {
        $ScriptOut  # Write ScriptOut to output stream.
    } else {
        Write-Error "$ErrorOut"  # Use Write-Error only here.
    }
    # exit $ExitCode
}