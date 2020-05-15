<#
.SYNOPSIS
    Short description

.DESCRIPTION
    Long description

    File-Name:  Add-NsxEdgeDhcpBinding.ps1
    Author:     David Wettstein
    Version:    v2.0.1

    Changelog:
                v2.0.1, 2020-05-07, David Wettstein: Reorganize input params.
                v2.0.0, 2020-04-23, David Wettstein: Refactor and get rid of PowerNSX.
                v1.0.3, 2020-04-09, David Wettstein: Improve path handling.
                v1.0.2, 2020-04-08, David Wettstein: Use helper Invoke-NsxRequest.
                v1.0.1, 2020-03-13, David Wettstein: Change AsObj to AsXml.
                v1.0.0, 2019-08-23, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    Example of how to use this cmdlet
#>
[CmdletBinding()]
[OutputType([Object])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern("^edge-\d+$")]
    [String] $EdgeId
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidatePattern("^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$")]
    [String] $MacAddress
    ,
    [Parameter(Mandatory = $true, Position = 2)]
    [ValidateNotNullOrEmpty()]
    [String] $Hostname
    ,
    [Parameter(Mandatory = $true, Position = 3)]
    [ValidatePattern("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")]
    [String] $IpAddress
    ,
    [Parameter(Mandatory = $true, Position = 4)]
    [ValidatePattern("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")]
    [String] $SubnetMask
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidatePattern("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$")]
    [String] $DefaultGateway
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [String] $DomainName
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [Int] $LeaseTime = 86400
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [String] $PrimaryNameServer
    ,
    [Parameter(Mandatory = $false, Position = 9)]
    [String] $SecondaryNameServer
    ,
    [Parameter(Mandatory = $false, Position = 10)]
    [String] $DhcpOptionNextServer
    ,
    [Parameter(Mandatory = $false, Position = 11)]
    [String] $DhcpOptionTFTPServer
    ,
    [Parameter(Mandatory = $false, Position = 12)]
    [String] $DhcpOptionBootfile
    ,
    [Parameter(Mandatory = $false, Position = 13)]
    [Switch] $AsXml
    ,
    [Parameter(Mandatory = $false, Position = 14)]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 15)]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 16)]
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
foreach ($Module in $Modules) {
    if (Get-Module | Where-Object { $_.Name -eq $Module }) {
        # Module already imported. Do nothing.
    } else {
        Import-Module $Module
    }
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
    # Template for request body
    [Xml] $Body = @"
<staticBinding>
    <macAddress></macAddress>
    <hostname></hostname>
    <ipAddress></ipAddress>
    <subnetMask></subnetMask>
    <leaseTime></leaseTime>
    <autoConfigureDNS>true</autoConfigureDNS>
    <dhcpOptions></dhcpOptions>
</staticBinding>
"@
#     [Xml] $Body = @"
# <staticBinding>
#     <macAddress></macAddress>
#     <hostname></hostname>
#     <ipAddress></ipAddress>
#     <subnetMask></subnetMask>
#     <defaultGateway></defaultGateway>
#     <domainName></domainName>
#     <leaseTime></leaseTime>
#     <autoConfigureDNS>true</autoConfigureDNS>
#     <primaryNameServer></primaryNameServer>
#     <secondaryNameServer></secondaryNameServer>
#     <nextServer></nextServer>
#     <dhcpOptions>
#         <option66></option66>
#         <option67></option67>
#     </dhcpOptions>
# </staticBinding>
# "@

    # Add values from input
    $Body.staticBinding.macAddress = $MacAddress
    $Body.staticBinding.hostname = $Hostname
    $Body.staticBinding.ipAddress = $IpAddress
    $Body.staticBinding.subnetMask = $SubnetMask
    if ($DefaultGateway) {
        Add-XmlElement $Body.staticBinding "defaultGateway" $DefaultGateway
        # $Body.staticBinding.defaultGateway = $DefaultGateway
    }
    if ($DomainName) {
        Add-XmlElement $Body.staticBinding "domainName" $DomainName
        # $Body.staticBinding.domainName = $DomainName
    }
    $Body.staticBinding.leaseTime = [String] $LeaseTime
    if ($PrimaryNameServer) {
        $Body.staticBinding.autoConfigureDNS = "false"
        Add-XmlElement $Body.staticBinding "primaryNameServer" $PrimaryNameServer
        # $Body.staticBinding.primaryNameServer = $PrimaryNameServer
    }
    if ($SecondaryNameServer) {
        $Body.staticBinding.autoConfigureDNS = "false"
        Add-XmlElement $Body.staticBinding "secondaryNameServer" $SecondaryNameServer
        # $Body.staticBinding.secondaryNameServer = $SecondaryNameServer
    }
    if ($DhcpOptionNextServer) {
        Add-XmlElement $Body.staticBinding "nextServer" $DhcpOptionNextServer
        # $Body.staticBinding.nextServer = $DhcpOptionNextServer
    }
    if ($DhcpOptionTFTPServer) {
        Add-XmlElement $Body.staticBinding.dhcpOptions "option66" $DhcpOptionTFTPServer
        # $Body.staticBinding.dhcpOptions.option66 = $DhcpOptionTFTPServer
    }
    if ($DhcpOptionBootfile) {
        Add-XmlElement $Body.staticBinding.dhcpOptions "option67" $DhcpOptionBootfile
        # $Body.staticBinding.dhcpOptions.option67 = $DhcpOptionBootfile
    }

    # Invoke API with this body
    $Endpoint = "/api/4.0/edges/$EdgeId/dhcp/config/bindings"
    if ($ApproveAllCertificates) {
        $Response = & "${FILE_DIR}Invoke-NsxRequest" -Server $Server -Method "POST" -Endpoint $Endpoint -Body $Body.OuterXml -AuthorizationToken $AuthorizationToken -ApproveAllCertificates
    } else {
        $Response = & "${FILE_DIR}Invoke-NsxRequest" -Server $Server -Method "POST" -Endpoint $Endpoint -Body $Body.OuterXml -AuthorizationToken $AuthorizationToken
    }
    if ($Response.StatusCode -lt 200 -or $Response.StatusCode -ge 300) {
        throw "Failed to invoke $($Endpoint): $($Response.StatusCode) - $($Response.Content)"
    }

    if ($AsXml) {
        $ScriptOut = $Response.Content
    } else {
        [Xml] $ResponseXml = $Response.Content
        $ScriptOut = $ResponseXml
    }
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
