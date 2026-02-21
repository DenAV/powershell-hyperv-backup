<#PSScriptInfo

.VERSION 21.02.2026

.AUTHOR DenAV

#>

<#
    .SYNOPSIS
    Hyper-V Backup Utility (Combined) — Full backup cycle in a single run.

    .DESCRIPTION
    This script performs a complete backup of Hyper-V virtual machines in one execution:
      1. Export running VMs
      2. Compress exports with 7-Zip (or Windows compression as fallback)
      3. Copy compressed backups to a remote destination
      4. Send email notification with the log

    This is the combined version of Backup-HPV(1 part).ps1 and Backup-HPV(2 part).ps1.
    Use this script when you want the entire backup pipeline to run in a single
    Task Scheduler job without a pause between export/compress and remote copy.

    For split execution (e.g., export overnight, copy in the morning),
    use Part 1 and Part 2 separately.

    .PARAMETER ExceptList
    Path to a text file with VM names to exclude from backup.

    .PARAMETER VmList
    Path to a text file with VM names to back up. If not set, all running VMs are backed up.

    .PARAMETER DiskWorkDir
    Local working directory for exports and compression.

    .PARAMETER L_History
    Number of days of local backups to keep.

    .PARAMETER R_History
    Number of days of remote backups to keep.

    .PARAMETER BackupDir
    Remote backup destination path.

    .PARAMETER SzThreadNo
    7-Zip thread count parameter (e.g. "mmt10").

    .PARAMETER SzCompL
    7-Zip compression level parameter (e.g. "mx1").

    .PARAMETER ShortDate
    Use short date format (yyyy-MM-dd) in archive filenames.

    .PARAMETER Encrypt
    Encrypt the archive with a password from the pwd-storage file.

    .PARAMETER DateTime
    Append time to the backup directory path.

    .PARAMETER ConfigFile
    Read all settings from backup-hpv.ini instead of command-line parameters.

    .EXAMPLE
    .\Backup-HPV(1-2 part).ps1 -ConfigFile
    Run the full backup pipeline using settings from backup-hpv.ini.

    .EXAMPLE
    .\Backup-HPV(1-2 part).ps1 -Disk E:\ -Backup \\server\backups -SzThreads mmt8 -SzComp mx5
    Run with custom local and remote paths, 8 threads, and medium compression.
#>

## Set up command line switches.
[CmdletBinding()]

Param(
    [Parameter(Mandatory=$False)]
    [alias("Except")] $ExceptList = $Null,
    [Parameter(Mandatory=$False)]
    [alias("VMs")] $VmList = $Null,
    [Parameter(Mandatory=$False)]
    [alias("Disk")] $DiskWorkDir = 'E:\',
    [Parameter(Mandatory=$False)]
    [alias("L_Keep")] $L_History = 1,
    [Parameter(Mandatory=$False)]
    [alias("R_Keep")] $R_History = 3,
    [Parameter(Mandatory=$False)]
    [alias("Backup")] $BackupDir = "\\backup.example.com\cloudtest-01\",
    [Parameter(Mandatory=$False)]
    [alias("SzThreads")] $SzThreadNo = 'mmt10',
    [Parameter(Mandatory=$False)]
    [alias("SzComp")] $SzCompL = 'mx1',
    [Parameter(Mandatory=$False)] [switch]$ShortDate = $False,
    [Parameter(Mandatory=$False)] [switch]$Encrypt = $True,
    [Parameter(Mandatory=$False)] [switch]$DateTime = $False,
    [Parameter(Mandatory=$False)] [switch]$ConfigFile = $False
)

$Error.Clear()

# Set the variable for the host name.
$HPV_Host = $Env:ComputerName

## Set a variable for the path of the script.
$ParentPath = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)

## Import the BackupHPV module with shared functions
$ModulePath = Join-Path -Path $ParentPath -ChildPath "modules\BackupHPV\BackupHPV.psm1"
if (Test-Path $ModulePath) {
    Import-Module $ModulePath -Force
} else {
    Write-Error "BackupHPV module not found at: $ModulePath"
    exit 1
}

if ($ConfigFile) {
    # Get configuration from INI file
    if (Test-Path (Join-Path -Path $ParentPath -ChildPath "backup-hpv.ini")) {

        $conf_ini = (Join-Path -Path $ParentPath -ChildPath "backup-hpv.ini") | Get-IniFile

        $DiskWorkDir = $conf_ini.local.directory
        $BackupDir = $conf_ini.backup.directory

        $L_History = $conf_ini.local.history
        $R_History = $conf_ini.backup.history

        $VmList = $conf_ini.path.vms_list
        $ExceptList = $conf_ini.path.vms_except

        # Read SMTP parameters from INI [mail] section
        if ($conf_ini.mail) {
            $SmtpServer = $conf_ini.mail.server
            $SmtpPort = $conf_ini.mail.port
            $SmtpUser = $conf_ini.mail.user
            $MailFrom = $conf_ini.mail.from
            $MailTo = $conf_ini.mail.to
            if ($conf_ini.mail.pwd) {
                $SmtpPwd = $conf_ini.mail.pwd
            }
        }
    } else {
        Write-Error "Configuration file backup-hpv.ini not found!"
        exit 1
    }
}

#################################################

# Logging
$LogPath = Join-Path -Path $ParentPath -ChildPath "Logging"

# For email body
$CountError = 0
$Job = "Backup-HPV (combined) job: The task of backing up VMs on the $HPV_Host"

# Default SMTP server authentication (overridden by INI [mail] section when -ConfigFile is used)
if (-not $SmtpServer) { $SmtpServer = 'mail.example.com' }
if (-not $SmtpPort)   { $SmtpPort = 587 }
$UseSsl = $True
if (-not $SmtpUser)   { $SmtpUser = 'backup-server@example.com' }
if (-not $SmtpPwd)    { $SmtpPwd = Join-Path -Path $ParentPath -ChildPath "pwd-storage.txt" }

# Email address
if (-not $MailFrom)   { $MailFrom = $SmtpUser }
if (-not $MailTo)     { $MailTo = 'monitoring@example.de' }
$MailSubject = $Null

# Date for backup directory naming
$Backup_Day = Get-DateShort

# Path to registry key for backup status tracking
$registory_key = "HKLM:\SOFTWARE\Backup-HPV"

## Functions Start-Copy_Daten, Export-StandardRunVM, and Compress-VM
## are provided by the BackupHPV module (modules/BackupHPV/BackupHPV.psm1)

########################################
##          START the Script          ##
########################################

if (Test-Path $registory_key) {
    # Clear all values in the registry key
    Get-Item -Path $registory_key | Select-Object -ExpandProperty Property |
        ForEach-Object -Process { Remove-ItemProperty -Path $registory_key -Name $_ }

    # Initialize registry values for tracking backup progress
    New-ItemProperty -Path $registory_key -Name "Date Backup-HPV" -Value $Backup_Day -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registory_key -Name "Result Backup-HPV" -Value "new" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registory_key -Name "Finished Backup-HPV" -Value $False -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registory_key -Name "Result Export" -Value "-" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registory_key -Name "Finished Export" -Value $False -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registory_key -Name "Result Zippen" -Value "-" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registory_key -Name "Finished Zippen" -Value $False -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registory_key -Name "Result Copy" -Value "-" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registory_key -Name "Finished Copy" -Value $False -PropertyType String -Force | Out-Null
}
else {
    Write-Error "Registry path $registory_key does not exist"
    throw
}

## Start logging
if ($LogPath) {
    $FileName = "$($Backup_Day) Backup-HPV (combined).log"
    $LogFile = "$($LogPath)\$($FileName)"

    if (-not (Test-Path -Path $LogPath)) {
        New-Item $LogPath -ItemType Directory -Force | Out-Null
        Write-Log -Type Info -Evt "Logging directory $LogFile doesn't exist. Creating it."
    }
    else {
        # Clean up old log files
        try {
            Clear-Log-History -LogPath $LogPath -History $R_History -LogFile $LogFile -ErrorAction 'Stop'

            if (Test-Path -Path $LogFile) {
                Clear-Content -Path $LogFile
            }
        }
        catch {
            $_.Exception.Message | Add-Content -Path $LogFile -Encoding ASCII -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") [ERROR] $_"
        }
    }
    Add-Content -Path $LogFile -Encoding ASCII -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") [INFO] Log started"
}
else {
    Write-Warning "Log path is not configured!"
}

Set-ItemProperty -Path $registory_key -Name "Result Backup-HPV" -Value "Running" -Force | Out-Null

# Validate local backup directory
if (![System.IO.Directory]::Exists($DiskWorkDir)) {
    Write-Log -LogFile $LogFile -Type Err -Evt "Local backup directory does not exist: $DiskWorkDir"
}
else {
    # Build backup directory paths
    if ($DateTime) {
        $WorkDir = "$($DiskWorkDir)\$($Backup_Day)\$(Get-DateTime)"
        $Backup = "$($BackupDir)\$($Backup_Day)\$(Get-DateTime)"
    }
    else {
        $WorkDir = "$($DiskWorkDir)\$($Backup_Day)"
        $Backup = "$($BackupDir)\$($Backup_Day)"
    }

    ##
    ## Display configuration
    ##
    Write-Log -LogFile $LogFile -Type Conf -Evt "************ Running with the following config *************."
    Write-Log -LogFile $LogFile -Type Conf -Evt "This virtual host:.......$HPV_Host."

    ## Build the list of VMs to back up
    if ($VmList -and (Get-Content $VmList)) {
        $CheckVM = Get-Content $VmList
    }
    else {
        $CheckVM = Get-VM | Where-Object { $_.State -eq "Running" } | Select-Object -ExpandProperty Name
    }

    ## Apply exception list if configured
    if ($ExceptList -and (Get-Content $ExceptList)) {
        Write-Log -LogFile $LogFile -Type Conf -Evt "VMs in exception list:"
        if ($CheckVM) {
            $Vms = [System.Collections.ArrayList]::new()
            $CheckVM | ForEach-Object {
                $isExcluded = (Get-Content $ExceptList).Contains($_)
                if ($isExcluded) {
                    Write-Log -LogFile $LogFile -Type Conf -Evt "...............$($_)"
                }
                else {
                    [void]$Vms.Add($_)
                }
            }
        }
        else {
            Write-Log -LogFile $LogFile -Type Info -Evt "No running VMs found"
        }
    }
    else {
        $Vms = $CheckVM
    }

    ## Process VMs if any are found
    if ($Vms.count -ne 0) {
        if ($Null -eq $SzThreadNo) { $SzThreadNo = "mmt1" }
        if ($Null -eq $SzCompL) { $SzCompL = "mx1" }

        Write-Log -LogFile $LogFile -Type Conf -Evt "VMs to backup:...........: $($Vms.Count)"

        $Vms | ForEach-Object {
            Write-Log -LogFile $LogFile -Type Conf -Evt ".........................$_"
        }

        Write-Log -LogFile $LogFile -Type Conf -Evt "Remote-Backup directory:........$Backup."
        Write-Log -LogFile $LogFile -Type Conf -Evt "Local-Working directory:.......$WorkDir."

        if ($Null -ne $L_History) { Write-Log -LogFile $LogFile -Type Conf -Evt "Local Backups to keep:.........$L_History days" }
        else { Write-Log -LogFile $LogFile -Type Conf -Evt "Local Backups to keep:.........No Config" }

        if ($Null -ne $R_History) { Write-Log -LogFile $LogFile -Type Conf -Evt "Remote Backups to keep:.........$R_History days" }
        else { Write-Log -LogFile $LogFile -Type Conf -Evt "Remote Backups to keep:.........No Config" }

        if ($Null -ne $LogPath) { Write-Log -LogFile $LogFile -Type Conf -Evt "Logs directory:..........$LogPath." }
        else { Write-Log -LogFile $LogFile -Type Conf -Evt "Logs directory:..........No Config" }

        if ($MailTo) { Write-Log -LogFile $LogFile -Type Conf -Evt "E-mail log to:...........$MailTo." }
        else { Write-Log -LogFile $LogFile -Type Conf -Evt "E-mail log to:...........No Config" }

        if ($MailFrom) { Write-Log -LogFile $LogFile -Type Conf -Evt "E-mail log from:.........$MailFrom." }
        else { Write-Log -LogFile $LogFile -Type Conf -Evt "E-mail log from:.........No Config" }

        if ($SmtpServer) { Write-Log -LogFile $LogFile -Type Conf -Evt "SMTP server:.............$SmtpServer." }
        else { Write-Log -LogFile $LogFile -Type Conf -Evt "SMTP server:.............No Config" }

        if ($SmtpPwd) { Write-Log -LogFile $LogFile -Type Conf -Evt "SMTP pwd file:...........$SmtpPwd." }
        else { Write-Log -LogFile $LogFile -Type Conf -Evt "SMTP pwd file:...........No Config" }

        Write-Log -LogFile $LogFile -Type Conf -Evt "7-zip threads:...........$SzThreadNo."
        Write-Log -LogFile $LogFile -Type Conf -Evt "7-zip compression:.......$SzCompL."
        Write-Log -LogFile $LogFile -Type Conf -Evt "**************************************************************"
        Write-Log -LogFile $LogFile -Type Info -Evt "Process started."

        ##
        ## Step 1: Delete old local backups
        ##
        try {
            Remove-OldDate -DirPath $DiskWorkDir -keep $L_History -LogFile $LogFile -ErrorAction 'Stop'
        }
        catch {
            Write-Log -LogFile $LogFile -Type Err -Evt $_.Exception.Message
        }

        ##
        ## Step 2: Export and compress each VM
        ##
        $Vms | Get-VM | Where-Object { $_.State -eq "Running" } | Select-Object -ExpandProperty Name | ForEach-Object {
            $count_export = 0
            do {
                try {
                    Set-ItemProperty -Path $registory_key -Name "Finished Export" -Value $False -Force | Out-Null

                    Export-StandardRunVM -ExportVmName $_ -ExportDirectory $WorkDir `
                                        -LogFile $LogFile -RegistryKey $registory_key

                    if ((Get-ItemPropertyValue -Path $registory_key -Name "Result Export") -ne "Success") {
                        $count_export += 1
                        Write-Log -LogFile $LogFile -Type Err -Evt "Attempting to export VM: $count_export, Sleep 10"
                        Start-Sleep 10
                    }
                }
                catch {
                    Write-Log -LogFile $LogFile -Type Err -Evt "Attempting to export VM: $count_export, $($_.Exception.Message)"
                    $count_export += 1
                    Start-Sleep 10
                }
            } until ((Get-ItemPropertyValue -Path $registory_key -Name "Result Export" -ErrorAction Ignore) -eq "Success" `
                    -or $count_export -ge 3)

            try {
                Set-ItemProperty -Path $registory_key -Name "Finished Zippen" -Value $False -Force | Out-Null
                Compress-VM -VmName $_ -WorkDir $WorkDir -LogFile $LogFile -RegistryKey $registory_key `
                            -SzThreads $SzThreadNo -SzCompression $SzCompL -ShortDate:$ShortDate `
                            -Encrypt:$Encrypt -EncryptionPwdFile $SmtpPwd
            }
            catch {
                Write-Log -LogFile $LogFile -Type Err -Evt $_.Exception.Message
                Set-ItemProperty -Path $registory_key -Name "Result Zippen" -Value "Failure" -Force | Out-Null
            }
        }

        Set-ItemProperty -Path $registory_key -Name "Finished Export" -Value $True -Force | Out-Null
        Set-ItemProperty -Path $registory_key -Name "Finished Zippen" -Value $True -Force | Out-Null

        ##
        ## Step 3: Copy to remote destination
        ##
        if ([System.IO.Directory]::Exists($BackupDir)) {
            if ([System.IO.Directory]::Exists($WorkDir)) {
                $count_copy = 0
                do {
                    try {
                        Set-ItemProperty -Path $registory_key -Name "Finished Copy" -Value $False -Force | Out-Null

                        Start-Copy_Daten -sourceDirPath $WorkDir -destDirPath $Backup `
                                         -LogFile $LogFile -RegistryKey $registory_key -ErrorAction 'Stop'

                        if ((Get-ItemPropertyValue -Path $registory_key -Name "Result Copy") -ne "Success") {
                            Write-Log -LogFile $LogFile -Type Err -Evt "Attempting to copy: $count_copy, Sleep 30"
                            $count_copy += 1
                            Start-Sleep 30
                        }
                    }
                    catch {
                        Write-Log -LogFile $LogFile -Type Err -Evt "Attempting to copy: $count_copy, $($_.Exception.Message), Sleep 30"
                        $count_copy += 1
                        Start-Sleep 30
                    }
                } until ((Get-ItemPropertyValue -Path $registory_key -Name "Result Copy") -eq "Success" `
                        -or $count_copy -ge 3)

                Set-ItemProperty -Path $registory_key -Name "Finished Copy" -Value $True -Force | Out-Null

                ## Delete old remote backups
                try {
                    Remove-OldDate -DirPath $BackupDir -keep $R_History -LogFile $LogFile -ErrorAction 'Stop'
                }
                catch {
                    Write-Log -LogFile $LogFile -Type Err -Evt $_.Exception.Message
                }
            }
            else {
                Write-Log -LogFile $LogFile -Type Err -Evt "Local backup directory not found: $WorkDir"
            }
        }
        else {
            Write-Log -LogFile $LogFile -Type Err -Evt "Remote backup directory is not reachable: $BackupDir"
        }

    } # if ($Vms.count -ne 0)
    else {
        Write-Log -LogFile $LogFile -Type Info -Evt "There are no VMs running to backup"
    }

} ## END local directory validation

##
## Determine overall result
##

# Search for errors in the log file
$CountError_LogFile = Select-String -Path $LogFile -SimpleMatch "[ERROR]"

# Set overall result based on all steps
if ((Get-ItemPropertyValue -Path $registory_key -Name "Result Export") -eq "Success" `
    -and (Get-ItemPropertyValue -Path $registory_key -Name "Result Zippen") -eq "Success" `
    -and (Get-ItemPropertyValue -Path $registory_key -Name "Result Copy") -eq "Success" `
    -and (Get-ItemPropertyValue -Path $registory_key -Name "Finished Export") -eq $True `
    -and (Get-ItemPropertyValue -Path $registory_key -Name "Finished Zippen") -eq $True `
    -and (Get-ItemPropertyValue -Path $registory_key -Name "Finished Copy") -eq $True `
    -and $CountError_LogFile.Count -le 0) {

    Set-ItemProperty -Path $registory_key -Name "Result Backup-HPV" -Value "Success" -Force | Out-Null
    Set-ItemProperty -Path $registory_key -Name "Finished Backup-HPV" -Value $True -Force | Out-Null
}
else {
    Set-ItemProperty -Path $registory_key -Name "Result Backup-HPV" -Value "Failure" -Force | Out-Null
    Set-ItemProperty -Path $registory_key -Name "Finished Backup-HPV" -Value $False -Force | Out-Null
}

Write-Log -LogFile $LogFile -Type Info -Evt "Process finished. Errors: $($CountError_LogFile.Count)"

##
## Send email notification
##
if ($LogPath) {
    Add-Content -Path $LogFile -Encoding ASCII -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") [INFO] Log finished"

    if ($SmtpServer) {
        # Build email subject from result
        if ($Null -eq $MailSubject) {
            if ($CountError_LogFile.Count -eq 0) {
                $MailSubject = "[Success]:[$HPV_Host] Backup-VMs Hyper-V Log"
            }
            else {
                $MailSubject = "[Failed]:[$HPV_Host] Backup-VMs Hyper-V Log"
            }
        }

        $MailBody = Get-Content -Path $LogFile | Out-String

        if ($SmtpPwd -and (Test-Path -Path $SmtpPwd)) {
            if ($UseSsl) {
                try {
                    EmailSenden -user $SmtpUser -to $MailTo -from $MailFrom -Subject $MailSubject `
                                -Job $Job -Fail $CountError_LogFile.Count -SSL $UseSsl `
                                -Body $MailBody -LogFile $LogFile -SmtpServer $SmtpServer `
                                -SmtpPort $SmtpPort -ErrorAction 'Stop'
                }
                catch {
                    Write-Log -LogFile $LogFile -Type Err -Evt $_.Exception.Message
                }
            }
        }
        else {
            Write-Log -LogFile $LogFile -Type Err -Evt "File with password for email does not exist. Please create"
        }
    }
}

Remove-Variable -Name * -ErrorAction SilentlyContinue

## End
