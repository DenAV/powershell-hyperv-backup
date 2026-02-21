<#
.SYNOPSIS
    BackupHPV PowerShell Module — shared functions for Hyper-V backup scripts.
.DESCRIPTION
    This module contains common functions used by Backup-HPV Part 1 and Part 2 scripts:
    - Start-Copy_Daten  : Copies backup data using Robocopy
    - Export-StandardRunVM : Exports a running Hyper-V VM
    - Compress-VM       : Compresses VM backup folder using 7-Zip or Windows compression
.NOTES
    Version: 1.0.0
    Author:  DenAV
    Requires: Hyper-V PowerShell module (for Export-VM)
    External dependencies: Write-Log, Get-DateShort, Get-DateLong (from ADVModule)
#>

#region Start-Copy_Daten

Function Start-Copy_Daten {
    <#
    .SYNOPSIS
        Copy backup data from source to destination using Robocopy.
    .DESCRIPTION
        Copies files and directories using Robocopy with restartable mode (/Z),
        automatic retries, and built-in directory recursion. Validates VHD/VHDX
        file sizes before copying. Updates a registry key with copy status.
    .PARAMETER sourceDirPath
        The source directory or file path.
    .PARAMETER destDirPath
        The destination directory path.
    .PARAMETER LogFile
        Path to the log file for Write-Log output.
    .PARAMETER RegistryKey
        Registry key path for writing copy status (Result Copy).
    .PARAMETER UpdatePipelineStatus
        When set, updates "Finished Copy" registry value based on export/compression
        pipeline status. Used by Part 2 when no new files need copying.
    .EXAMPLE
        Start-Copy_Daten -sourceDirPath "E:\2025-01-15" -destDirPath "\\server\backup\2025-01-15" -LogFile "C:\Logs\backup.log" -RegistryKey "HKLM:\SOFTWARE\Backup-HPV"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string] $sourceDirPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $destDirPath,

        [Parameter(Mandatory=$False)]
        [string] $LogFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RegistryKey,

        [switch] $UpdatePipelineStatus
    )
    process {
        Write-Log -LogFile $LogFile -Type Info -Evt "Backup copy started for $($sourceDirPath)."
        $copy_success = $False
        Set-ItemProperty -Path $RegistryKey -Name "Result Copy" -Value "Running" -Force | Out-Null

        # Verify source path exists
        if (-not (Test-Path -Path $sourceDirPath)) {
            Write-Log -LogFile $LogFile -Type Err -Evt "Source path does not exist: $sourceDirPath"
            Set-ItemProperty -Path $RegistryKey -Name "Result Copy" -Value "Failure" -Force | Out-Null
            return
        }

        if ((Get-Item -Path $sourceDirPath).PSIsContainer) {
            # Pre-copy validation: check for suspiciously small VHD/VHDX files (< 100MB)
            [string[]]$smallVhdFiles = @()
            Get-ChildItem -Path $sourceDirPath -Recurse -File -ErrorAction Ignore |
                Where-Object { $_.Extension -match '\.(vhdx?|avhdx?)$' -and $_.Length -lt 100MB } |
                ForEach-Object {
                    $smallVhdFiles += $_.Name
                    Write-Log -LogFile $LogFile -Type Err -Evt "$($_.Name) is suspiciously small: $([string]::Format('{0:0.00} KB', $_.Length / 1KB))"
                }

            # Robocopy arguments:
            #   /E     — copy subdirectories including empty ones
            #   /Z     — restartable mode (resume on network failure)
            #   /R:3   — retry 3 times on failure
            #   /W:10  — wait 10 seconds between retries
            #   /NP    — no progress percentage in output
            #   /NDL   — no directory listing in log
            #   /XF    — exclude tmp_* files
            Write-Log -LogFile $LogFile -Type Info -Evt "Running Robocopy: $sourceDirPath -> $destDirPath"

            $robocopyOutput = & robocopy.exe $sourceDirPath $destDirPath /E /Z /R:3 /W:10 /NP /NDL /XF tmp_* 2>&1
            $robocopyExitCode = $LASTEXITCODE

            # Robocopy exit codes:
            #   0   — no files copied, no errors
            #   1   — files copied successfully
            #   2   — extra files/dirs detected in destination
            #   4   — mismatched files detected
            #   8   — some files could not be copied (error)
            #   16  — fatal error, no files copied
            # Codes 0-7 are considered successful
            if ($robocopyExitCode -lt 8) {
                $copy_success = $True
                Write-Log -LogFile $LogFile -Type Succ -Evt "Robocopy completed successfully (exit code: $robocopyExitCode)."
            }
            else {
                $copy_success = $False
                Write-Log -LogFile $LogFile -Type Err -Evt "Robocopy failed with exit code: $robocopyExitCode."
                # Log last lines of Robocopy output for diagnostics
                $robocopyOutput | Select-Object -Last 5 | ForEach-Object {
                    Write-Log -LogFile $LogFile -Type Err -Evt "Robocopy: $_"
                }
            }

            # Fail the copy if suspiciously small VHD/VHDX files were detected
            if ($smallVhdFiles.Count -gt 0 -and $copy_success) {
                Write-Log -LogFile $LogFile -Type Err -Evt "Backup contains suspiciously small VHD/VHDX files — marking as failed."
                $copy_success = $False
            }

            # Part 2 specific: update "Finished Copy" based on pipeline status
            if ($UpdatePipelineStatus -and $robocopyExitCode -eq 0 -and $smallVhdFiles.Count -eq 0) {
                # No new files to copy and no errors — check if export and compression are done
                if ((Get-ItemPropertyValue -Path $RegistryKey -Name "Finished Export") -eq $True `
                    -and (Get-ItemPropertyValue -Path $RegistryKey -Name "Finished Zippen") -eq $True) {
                    Set-ItemProperty -Path $RegistryKey -Name "Finished Copy" -Value $True -Force | Out-Null
                }
                else {
                    Set-ItemProperty -Path $RegistryKey -Name "Finished Copy" -Value $False -Force | Out-Null
                }
            }
        }
        else {
            # Source is a single file — use Robocopy for single file copy
            $sourceDir = Split-Path -Path $sourceDirPath -Parent
            $sourceFile = Split-Path -Path $sourceDirPath -Leaf

            try {
                & robocopy.exe $sourceDir $destDirPath $sourceFile /Z /R:3 /W:10 /NP 2>&1 | Out-Null
                if ($LASTEXITCODE -lt 8) {
                    $copy_success = $True
                }
                else {
                    throw "Robocopy failed to copy file $sourceFile (exit code: $LASTEXITCODE)"
                }
            }
            catch {
                Write-Log -LogFile $LogFile -Type Err -Evt $_.Exception.Message
                $copy_success = $False
            }
        }

        # Set final result in registry
        if ($copy_success) {
            Write-Log -LogFile $LogFile -Type Info -Evt "Folder backed up successfully: $sourceDirPath."
            Set-ItemProperty -Path $RegistryKey -Name "Result Copy" -Value "Success" -Force | Out-Null
        }
        else {
            Write-Log -LogFile $LogFile -Type Err -Evt "Folder backup completed with errors: $sourceDirPath."
            Set-ItemProperty -Path $RegistryKey -Name "Result Copy" -Value "Failure" -Force | Out-Null
        }
    } # END Process
} # END Function Start-Copy_Daten

#endregion

#region Export-StandardRunVM

Function Export-StandardRunVM {
    <#
    .SYNOPSIS
        Export a running Hyper-V virtual machine.
    .DESCRIPTION
        Exports a virtual machine to a specified directory. Removes any existing
        backup folder for the VM before exporting. Updates registry with export status.
    .PARAMETER ExportVmName
        The name of the virtual machine to export.
    .PARAMETER ExportDirectory
        The directory to export the virtual machine to.
    .PARAMETER LogFile
        The log file to write logs to.
    .PARAMETER RegistryKey
        The registry key to write the export status to.
    .NOTES
        Requires Hyper-V PowerShell module.
    .EXAMPLE
        Export-StandardRunVM -ExportVmName "VM1" -ExportDirectory "C:\Exports" -LogFile "C:\Logs\export.log" -RegistryKey "HKLM:\SOFTWARE\Backup-HPV"
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$True, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$ExportVmName,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$ExportDirectory,

        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$RegistryKey,

        [Parameter(Mandatory=$False)]
        [string]$LogFile
    )
    process {
        $StatusExport = $False

        if (-not (Test-Path -Path $RegistryKey)) {
            Write-Log -LogFile $LogFile -Type Err -Evt "Registry key $RegistryKey does not exist."
            throw "Registry key $RegistryKey does not exist."
        }
        Set-ItemProperty -Path $RegistryKey -Name "Result Export" -Value "Running" -Force | Out-Null

        $BackupPath = Join-Path -Path $ExportDirectory -ChildPath $ExportVmName

        if (Test-Path -Path $BackupPath -PathType Container) {
            Write-Log -LogFile $LogFile -Type Info -Evt "Removing existing backup folder for VM: $ExportVmName"
            try {
                Remove-Item -Path $BackupPath -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Log -LogFile $LogFile -Type Err -Evt "Error deleting backup folder: $($_.Exception.Message)"
                throw "Error deleting backup folder"
            }
        }

        # Export virtual machine
        try {
            Write-Log -LogFile $LogFile -Type Info -Evt "Attempting to export VM: $ExportVmName"
            $ExportVmName | Export-VM -Path $ExportDirectory -ErrorAction 'Stop'
            $StatusExport = $True
        } catch {
            Write-Log -LogFile $LogFile -Type Err -Evt "Export failed: $($_.Exception.Message)"
            $StatusExport = $False
        }
    }
    end {
        if ($StatusExport) {
            Write-Log -LogFile $LogFile -Type Succ -Evt "VM: $ExportVmName exported successfully."
            Set-ItemProperty -Path $RegistryKey -Name "Result Export" -Value "Success" -Force | Out-Null
        } else {
            Write-Log -LogFile $LogFile -Type Err -Evt "VM: $ExportVmName export failed."
            Set-ItemProperty -Path $RegistryKey -Name "Result Export" -Value "Failure" -Force | Out-Null
        }

        return [PSCustomObject]@{
            VMName       = $ExportVmName
            ExportStatus = $StatusExport
            Timestamp    = Get-Date
        }
    }
} # END Function Export-StandardRunVM

#endregion

#region Compress-VM

Function Compress-VM {
    <#
    .SYNOPSIS
        Compress a VM backup folder using 7-Zip or Windows built-in compression.
    .DESCRIPTION
        Compresses the exported VM folder into a .7z or .zip archive. Uses a temporary
        filename prefix (tmp_) during compression and renames after completion.
        If 7-Zip is installed, it is used with configurable threads and compression level.
        Optionally encrypts the archive with a password from a secure file.
        Falls back to Windows .NET compression if 7-Zip is not found.
        Removes the original VM export folder after successful compression.
    .PARAMETER VmName
        The name of the VM whose backup folder should be compressed.
    .PARAMETER WorkDir
        The working directory containing the VM export folder.
    .PARAMETER LogFile
        Path to the log file for Write-Log output.
    .PARAMETER RegistryKey
        Registry key path for writing compression status (Result Zippen).
    .PARAMETER SzThreads
        7-Zip thread count parameter (e.g. "mmt10"). Default: "mmt1".
    .PARAMETER SzCompression
        7-Zip compression level parameter (e.g. "mx1"). Default: "mx1".
    .PARAMETER ShortDate
        Use short date format (yyyy-MM-dd) in archive filenames.
    .PARAMETER Encrypt
        Encrypt the archive with a password.
    .PARAMETER EncryptionPwdFile
        Path to the file containing the encrypted password for 7-Zip encryption.
    .EXAMPLE
        Compress-VM -VmName "DC01" -WorkDir "E:\2025-01-15" -LogFile "C:\Logs\backup.log" -RegistryKey "HKLM:\SOFTWARE\Backup-HPV" -SzThreads "mmt8" -SzCompression "mx5"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$VmName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkDir,

        [Parameter(Mandatory=$False)]
        [string]$LogFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RegistryKey,

        [Parameter(Mandatory=$False)]
        [string]$SzThreads = "mmt1",

        [Parameter(Mandatory=$False)]
        [string]$SzCompression = "mx1",

        [switch]$ShortDate,

        [switch]$Encrypt,

        [Parameter(Mandatory=$False)]
        [string]$EncryptionPwdFile
    )

    Write-Log -LogFile $LogFile -Type Info -Evt "Compressing VM: $VmName backup using 7-Zip compression"

    # Build archive filename based on date format
    if ($ShortDate) {
        $ShortDateT = Test-Path -Path ("$WorkDir\$VmName-$(Get-DateShort).*z*")

        if ($ShortDateT) {
            Write-Log -LogFile $LogFile -Type Info -Evt "File $VmName-$(Get-DateShort) already exists, appending number"
            $i = 1
            $ShortDateNN = ("$VmName-$(Get-DateShort)-{0:D3}" -f $i++)
            $ShortDateExistT = Test-Path -Path "$WorkDir\$ShortDateNN.*z*"

            if ($ShortDateExistT) {
                do {
                    $ShortDateNN = ("$VmName-$(Get-DateShort)-{0:D3}" -f $i++)
                    $ShortDateExistT = Test-Path -Path "$WorkDir\$ShortDateNN.*z*"
                } until ($ShortDateExistT -eq $false)
            }

            $ArchivName = $ShortDateNN
        }
        $tmp_ArchivName = "tmp_$($VmName)-$(Get-DateShort)"
        $ArchivName = "$VmName-$(Get-DateShort)"
    }
    else {
        $tmp_ArchivName = "tmp_$($VmName)-$(Get-DateLong)"
        $ArchivName = "$VmName-$(Get-DateLong)"
    }

    # Test for 7-Zip installation
    $path_7zip = "C:\Programme\7-Zip\7z.exe"

    if (Test-Path $path_7zip) {

        if ($Encrypt -and $EncryptionPwdFile -and (Test-Path -Path $EncryptionPwdFile)) {

            $SecurePassword = Get-Content $EncryptionPwdFile | ConvertTo-SecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
            $PwdEncrypt = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

            Set-ItemProperty -Path $RegistryKey -Name "Result Zippen" -Value "Running" -Force | Out-Null
            & $path_7zip -$SzThreads -$SzCompression -bso0 a -t7z -m0=LZMA2:d64k:fb32 -ms=8m -p"$PwdEncrypt" -mhe -- ("$WorkDir\$tmp_ArchivName") "$WorkDir\$VmName\*"
        } else {
            Set-ItemProperty -Path $RegistryKey -Name "Result Zippen" -Value "Running" -Force | Out-Null
            & $path_7zip -$SzThreads -$SzCompression -bso0 a -t7z -m0=LZMA2:d64k:fb32 -ms=8m -- ("$WorkDir\$tmp_ArchivName") "$WorkDir\$VmName\*"
        }

        # Check 7-Zip exit code
        if ($LASTEXITCODE -ne 0) {
            Write-Log -LogFile $LogFile -Type Err -Evt "7-Zip failed with exit code: $LASTEXITCODE"
            Set-ItemProperty -Path $RegistryKey -Name "Result Zippen" -Value "Failure" -Force | Out-Null
            return
        }

        # Rename tmp_* 7z files to final name
        try {
            Get-ChildItem -Path $WorkDir -Filter "$tmp_ArchivName.7z" -File | Rename-Item -NewName "$ArchivName.7z"

            $zip_file_length = "$($WorkDir)\$ArchivName.7z" | Get-Item | Select-Object -ExpandProperty Length
            Write-Log -LogFile $LogFile -Type Succ -Evt "VM: $VmName compressed successfully as $ArchivName.7z ($([string]::Format("{0:0.00} KB", $zip_file_length/1KB)))"

            Set-ItemProperty -Path $RegistryKey -Name "Result Zippen" -Value "Success" -Force | Out-Null
        }
        catch {
            Write-Log -LogFile $LogFile -Type Err -Evt $_.Exception.Message
            Set-ItemProperty -Path $RegistryKey -Name "Result Zippen" -Value "Failure" -Force | Out-Null
        }
    }
    # Fallback: compress using Windows built-in compression
    else {
        Add-Type -AssemblyName "system.io.compression.filesystem"
        [io.compression.zipfile]::CreateFromDirectory("$WorkDir\$VmName", ("$WorkDir\$tmp_ArchivName.zip"))

        # Rename tmp_* zip files to final name
        try {
            Set-ItemProperty -Path $RegistryKey -Name "Result Zippen" -Value "Running" -Force | Out-Null

            Get-ChildItem -Path $WorkDir -Filter "$tmp_ArchivName.zip" -File | Rename-Item -NewName "$ArchivName.zip"
            $zip_file_length = "$($WorkDir)\$ArchivName.zip" | Get-Item | Select-Object -ExpandProperty Length
            Write-Log -LogFile $LogFile -Type Succ -Evt "VM: $VmName compressed successfully as $ArchivName.zip ($([string]::Format("{0:0.00} KB", $zip_file_length/1KB)))"
            Set-ItemProperty -Path $RegistryKey -Name "Result Zippen" -Value "Success" -Force | Out-Null
        }
        catch {
            Write-Log -LogFile $LogFile -Type Err -Evt $_.Exception.Message
            Set-ItemProperty -Path $RegistryKey -Name "Result Zippen" -Value "Failure" -Force | Out-Null
        }
    }

    # Remove the VM export folder after compression
    Get-ChildItem -Path $WorkDir -Filter "$VmName" -Directory | Remove-Item -Recurse -Force
} # END Function Compress-VM

#endregion

# Export all public functions
Export-ModuleMember -Function Start-Copy_Daten, Export-StandardRunVM, Compress-VM
