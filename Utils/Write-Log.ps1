<#
.SYNOPSIS
    Logs a given message with defined stream to stream and log-file.

.DESCRIPTION
    Logs a given message with defined stream to stream and log-file.

    NOTE: The parameter "Stream" is only needed for the function Write-Log. The usual
    functions Log-Host, Log-Output, Log-Verbose, Log-Warning, Log-Error and Log-Debug
    already include this parameter.

    VERBOSE and DEBUG:
    Use the -Verbose option to see the Write-Verbose outputs in the console.
    Use the -Debug option to see the Write-Debug outputs in the console.

    File-Name:  Write-Log.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2020-01-03, David Wettstein: First implementation, based on Logger module.

.NOTES
    Copyright (c) 2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.PARAMETER Stream
    The stream for the message (Host, Output, Verbose, Warning, Error).
    (Default is Output)

.PARAMETER Message
    The message to write into a file and display in the console.

.EXAMPLE
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [ValidateSet("Host", "Output", "Verbose", "Warning", "Error", "Debug")]
    [String] $Stream
    ,
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1)]
    [String] $Message
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [String] $LogFileRoot
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
# Use comma as output field separator (special variable $OFS).
$private:OFS = ","

# If this script was called from another script use its name for the log entry.
if (-not [String]::IsNullOrEmpty($MyInvocation.PSCommandPath)) {
    [String] $FILE_NAME = Get-ChildItem $MyInvocation.PSCommandPath | Select-Object -Expand Name
    [String] $FILE_DIR = Split-Path -Parent $MyInvocation.PSCommandPath
} else {
    [String] $FILE_NAME = $MyInvocation.MyCommand.Name
    if ($PSVersionTable.PSVersion.Major -lt 3 -or [String]::IsNullOrEmpty($PSScriptRoot)) {
        [String] $FILE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
    } else {
        [String] $FILE_DIR = $PSScriptRoot
    }
}

if ([String]::IsNullOrEmpty($LogFileRoot)) {
    [String] $LogFileName = $FILE_DIR + "\" + $FILE_NAME + "_" + (Get-Date -Format "yyyy-MM-dd") + ".log"
} else {
    [String] $LogFileName = $LogFileRoot + "\" + $FILE_NAME + "_" + (Get-Date -Format "yyyy-MM-dd") + ".log"
}
$LogDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffzzz"  # ISO8601

[Boolean] $IsVerboseGiven = $VerbosePreference -ne "SilentlyContinue"
[Boolean] $IsDebugGiven = $DebugPreference -ne "SilentlyContinue"

switch ($Stream) {
    Host {
        Write-Output "$LogDate | $FILE_NAME | $PID | HOST | $Message" | Out-File -FilePath $LogFileName -Append
        Write-Host $Message
        break
    }
    Output {
        Write-Output "$LogDate | $FILE_NAME | $PID | OUTPUT | $Message" | Out-File -FilePath $LogFileName -Append
        Write-Output $Message
        break
    }
    Verbose {
        if ($IsVerboseGiven) {
            Write-Output "$LogDate | $FILE_NAME | $PID | VERBOSE | $Message" | Out-File -FilePath $LogFileName -Append
        }
        Write-Verbose $Message
        break
    }
    Warning {
        Write-Output "$LogDate | $FILE_NAME | $PID | WARNING | $Message" | Out-File -FilePath $LogFileName -Append -Force
        Write-Warning $Message -WarningAction Continue
        break
    }
    Error {
        Write-Output "$LogDate | $FILE_NAME | $PID | ERROR | $Message" | Out-File -FilePath $LogFileName -Append -Force
        Write-Error $Message
        break
    }
    Debug {
        if ($IsDebugGiven) {
            Write-Output "$LogDate | $FILE_NAME | $PID | DEBUG | $Message" | Out-File -FilePath $LogFileName -Append -Force
        }
        Write-Debug $Message
        break
    }
    default {
        Write-Output "$LogDate | $FILE_NAME | $PID | DEFAULT | $Message" | Out-File -FilePath $LogFileName -Append
        break
    }
}

Remove-Variable IsVerboseGiven, IsDebugGiven
Remove-Variable LogDate
Remove-Variable Stream, Message