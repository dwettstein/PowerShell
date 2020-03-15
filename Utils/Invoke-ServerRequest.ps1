<#
.SYNOPSIS
    Wrapper cmdlet for directly invoking any RESTful API request on the given server,
    using the provided authorization token, e.g. "Basic username:password", or an existing PSCredential for authentication.

.DESCRIPTION
    Wrapper cmdlet for directly invoking any RESTful API request on the given server,
    using the provided authorization token, e.g. "Basic username:password", or an existing PSCredential for authentication.

    File-Name:  Invoke-ServerRequest.ps1
    Author:     David Wettstein
    Version:    v1.0.1

    Changelog:
                v1.0.1, 2020-03-13, David Wettstein: Refactor and generalize cmdlet.
                v1.0.0, 2019-05-30, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2019-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShell

.EXAMPLE
    $Result = & ".\Invoke-ServerRequest.ps1" "example.com" "/api/v1/version" -AuthorizationToken $AuthorizationToken

.EXAMPLE
    [Xml] $Result = & "$PSScriptRoot\Invoke-ServerRequest.ps1" -Server "example.com" -Endpoint "/api/v1/version" -Method "GET" -MediaType "application/*+xml" -AcceptAllCertificates
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [String] $Server
    ,
    [Parameter(Mandatory = $true, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [String] $Endpoint
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'UPDATE', 'DELETE')]
    [String] $Method = "GET"
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [ValidateNotNullOrEmpty()]
    [String] $Body = $null
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [ValidateSet('application/*', 'application/json', 'application/xml', 'application/*+xml', 'application/x-www-form-urlencoded', 'multipart/form-data', 'text/plain', 'text/xml', IgnoreCase = $false)]
    [String] $MediaType = "application/json"
    ,
    [Parameter(Mandatory = $false, Position = 5)]
    [ValidateNotNullOrEmpty()]
    [String] $AuthorizationHeader = "Authorization"
    ,
    [Parameter(Mandatory = $false, Position = 6)]
    [ValidateNotNullOrEmpty()]
    [String] $AuthorizationToken = $null  # secure string or plain text (not recommended)
    ,
    [Parameter(Mandatory = $false, Position = 7)]
    [ValidateSet('http', 'https', IgnoreCase = $false)]
    [String] $Protocol = "https"
    ,
    [Parameter(Mandatory = $false, Position = 8)]
    [Switch] $AcceptAllCertificates = $false
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
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
if ($PSVersionTable.PSVersion.Major -lt 3) {
    [String] $FILE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
} else {
    [String] $FILE_DIR = $PSScriptRoot
}

$ExitCode = 0
$ErrorOut = ""
$ScriptOut = ""

Write-Verbose "$($FILE_NAME): CALL."

function Approve-AllCertificates {
    $CSSource = @'
using System.Net;

public class ServerCertificate {
    public static void approveAllCertificates() {
        ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
    }
}
'@
    if (-not ([System.Management.Automation.PSTypeName]'ServerCertificate').Type) {
        Add-Type -TypeDefinition $CSSource
    }
    # Ignore self-signed SSL certificates.
    [ServerCertificate]::approveAllCertificates()
    # Disable certificate revocation check.
    [System.Net.ServicePointManager]::CheckCertificateRevocationList = $false;
    # Allow all security protocols.
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
}

#===============================================================================
# Main
#===============================================================================
#trap { Write-Error $_; exit 1; break; }

try {
    if ($AcceptAllCertificates) {
        Approve-AllCertificates
    }

    $BaseUrl = "${Protocol}://$Server"
    $EndpointUrl = "${BaseUrl}${endpoint}"

    $Headers = @{
        "Accept" = "$MediaType"
        "Content-Type" = "$MediaType"
        "Cache-Control" = "no-cache"
    }

    # If no AuthorizationToken is given, try to get it.
    if ([String]::IsNullOrEmpty($AuthorizationToken)) {
        try {
            $AuthorizationCred = & "$FILE_DIR\Get-PSCredential.ps1" -Server $Server
            $AuthorizationToken = ConvertFrom-SecureString $AuthorizationCred.Password
        } catch {
            Write-Verbose "$($_.Exception.Message)"
            # Ignore errors and try the request unauthorized.
        }
    }
    # If AuthorizationToken is given as SecureString string, convert it to plain text.
    try {
        $AuthorizationTokenSecureString = ConvertTo-SecureString -String $AuthorizationToken
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AuthorizationTokenSecureString)
        $AuthorizationToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        $null = [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    } catch {
        # AuthorizationToken was already given as plain text.
    }
    if (-not [String]::IsNullOrEmpty($AuthorizationToken)) {
        $Headers."$AuthorizationHeader" = "$AuthorizationToken"
    }

    if ($Body) {
        $Response = Invoke-WebRequest -Method $Method -Headers $Headers -Uri $EndpointUrl -Body $Body
    } else {
        $Response = Invoke-WebRequest -Method $Method -Headers $Headers -Uri $EndpointUrl
    }

    $ScriptOut = "$Response"
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