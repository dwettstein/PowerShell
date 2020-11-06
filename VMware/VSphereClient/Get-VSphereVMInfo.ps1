<#
.SYNOPSIS
    Get information about a VM.

.DESCRIPTION
    Get information about a VM.

    File-Name:  Get-VSphereVMInfo.ps1
    Author:     David Wettstein
    Version:    v1.0.0

    Changelog:
                v1.0.0, 2020-11-04, David Wettstein: Refactor script and release.
                v0.0.1, 2018-03-22, David Wettstein: First implementation.

.NOTES
    Copyright (c) 2018-2020 David Wettstein,
    licensed under the MIT License (https://dwettstein.mit-license.org/)

.LINK
    https://github.com/dwettstein/PowerShellStuff

.EXAMPLE
    $Result = & "Get-VSphereVMInfo" -Server "vcenter.vsphere.local" -Name "vm_name"
#>
[CmdletBinding()]
[OutputType([String])]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [Alias("VMName")]
    [String] $Name
    ,
    [Parameter(Mandatory = $false, Position = 1)]
    [Alias("VCenter")]
    [String] $Server
    ,
    [Parameter(Mandatory = $false, Position = 2)]
    [Object] $VSphereConnection
    ,
    [Parameter(Mandatory = $false, Position = 3)]
    [Switch] $Disconnect
    ,
    [Parameter(Mandatory = $false, Position = 4)]
    [Alias("Insecure")]
    [Switch] $ApproveAllCertificates
)

begin {
    if (-not $PSCmdlet.MyInvocation.BoundParameters.ErrorAction) { $ErrorActionPreference = "Stop" }
    if (-not $PSCmdlet.MyInvocation.BoundParameters.WarningAction) { $WarningPreference = "SilentlyContinue" }
    # Use comma as output field separator (special variable $OFS).
    $private:OFS = ","

    $StartDate = [DateTime]::Now
    $ExitCode = 0

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

    Write-Verbose "$($FILE_NAME): CALL."

    # Make sure the necessary modules are loaded.
    $Modules = @(
        "VMware.VimAutomation.Core"
    )
    $LoadedModules = Get-Module; $Modules | ForEach-Object {
        if ($_ -notin $LoadedModules.Name) { Import-Module $_ -DisableNameChecking }
    }
}

process {
    #trap { Write-Error "$($_.Exception)"; $ExitCode = 1; break; }
    $ScriptOut = ""
    $ErrorOut = ""

    try {
        $Server = & "${FILE_DIR}Sync-VSphereVariableCache" "Server" $Server -IsMandatory
        $VSphereConnection = & "${FILE_DIR}Sync-VSphereVariableCache" "VSphereConnection" $VSphereConnection
        $ApproveAllCertificates = [Boolean] (& "${FILE_DIR}Sync-VSphereVariableCache" "ApproveAllCertificates" $PSCmdlet.MyInvocation.BoundParameters.ApproveAllCertificates)

        if (-not $VSphereConnection) {
            $VSphereConnection = & "${FILE_DIR}Connect-VSphere" -Server $Server -ApproveAllCertificates:$ApproveAllCertificates
        }

        $VM = Get-VM -Server $Server -Name $Name
        $VMView = Get-View -VIObject $VM

        $ResultObj = @{
            "Name" = $VM.Name
            "Id" = $VM.Id
            "Uuid" = $VMView.Summary.Config.Uuid
            "PowerState" = $VM.PowerState
            "NumCpu" = $VM.NumCpu
            "MemoryGB" = $VM.MemoryGB
            "VMHost" = $VM.VMHost.Name
            "Cluster" = $VM.VMHost.Parent.Name
            "Version" = "$($VM.Version)"
            "UsedSpaceGB" = [Math]::round($VM.UsedSpaceGB)
            "ProvisionedSpaceGB" = [Math]::round($VM.ProvisionedSpaceGB)
            "ResourcePool" = $VM.ResourcePool.Name
            "Folder" = $VM.Folder.Name
            "VMXPath" = $VM.ExtensionData.Summary.Config.VmPathName
            "IPAddresses" = $VM.Guest.IPAddress
            "Snapshots" = @()
            "Disks" = @()
            "Nics" = @()
        }  # Build your result object (hashtable)

        $Snapshots = Get-Snapshot -Server $Server -VM $VM
        foreach ($Snap in $Snapshots) {
            $Row = @{}
            $Row.Name = $Snap.Name
            $Row.Id = $Snap.Id
            $Row.PowerState = $Snap.PowerState
            $Row.Created = Get-Date $Snap.Created -Format "yyyy-MM-ddTHH:mm:ss.fffzzz"  # ISO8601
            $Row.Description = [Regex]::Unescape($Snap.Description)
            $Row.IsCurrent = $Snap.IsCurrent
            $ResultObj.Snapshots += $Row
        }

        $Disks = Get-HardDisk -Server $Server -VM $VM
        foreach ($Disk in $Disks) {
            $Row = @{}
            $Row.Name = $Disk.Name
            $Row.Id = $Disk.Id
            $Row.CapacityGB = [Math]::round($Disk.CapacityGB)
            $Row.Filename = $Disk.Filename
            $Row.StorageFormat = "$($Disk.StorageFormat)"
            # $DatastoreTemp = $Disk.Filename.Split()[0]
            # $Row.Datastore = $DatastoreTemp.Substring(1, $DatastoreTemp.Length - 2)
            $Row.DatastoreId = "$($Disk.ExtensionData.Backing.Datastore)"
            if ($Row.DatastoreId) {
                $Row.Datastore = (Get-Datastore -Id $Row.DatastoreId).Name
            } else {
                $Row.Datastore = ""
            }
            $Row.Uuid = $Disk.ExtensionData.Backing.Uuid
            $Row.UnitNumber = $Disk.ExtensionData.UnitNumber
            $ResultObj.Disks += $Row
        }

        $Nics = Get-NetworkAdapter -Server $Server -VM $VM
        foreach ($Nic in $Nics) {
            $Row = @{}
            $Row.Name = $Nic.Name
            $Row.Id = $Nic.Id
            $Row.NetworkName = $Nic.NetworkName
            $Row.MacAddress = $Nic.MacAddress
            $Row.Type = "$($Nic.Type)"
            $Row.Connected = $Nic.ConnectionState.Connected
            $Row.StartConnected = $Nic.ConnectionState.StartConnected
            $ResultObj.Nics += $Row
        }

        # Return the result object as a JSON string. The parameter depth is needed to convert all child objects.
        $ScriptOut = ConvertTo-Json $ResultObj -Depth 10 -Compress
    } catch {
        # Error in $_ or $Error[0] variable.
        Write-Warning "Exception occurred at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)`n$($_.Exception)" -WarningAction Continue
        $Ex = $_.Exception; while ($Ex.InnerException) { $Ex = $Ex.InnerException }
        $ErrorOut = "$($Ex.Message)"
        $ExitCode = 1
    } finally {
        if ($Disconnect -and $VSphereConnection) {
            $null = Disconnect-VIServer -Server $VSphereConnection -Confirm:$false
        }

        if ([String]::IsNullOrEmpty($ErrorOut)) {
            $ScriptOut  # Write ScriptOut to output stream.
        } else {
            Write-Error "$ErrorOut"  # Use Write-Error only here.
        }
    }
}

end {
    Write-Verbose "$($FILE_NAME): ExitCode: $ExitCode. Execution time: $(([DateTime]::Now - $StartDate).TotalMilliseconds) ms. Started: $($StartDate.ToString('yyyy-MM-dd HH:mm:ss.fffzzz'))."
    # exit $ExitCode
}