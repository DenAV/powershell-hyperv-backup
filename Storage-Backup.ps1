# Aufgabe für das Skript
# TODO Vor Backup soll das Skript wie Daten Groß prüfen. Wenn Datei kleine als 10 Mb ist, soll Fehlmeldungen senden.

## Das Skript soll Daten zu Storagebox übertragen und alter Daten löschen.
## Set up command line switches.
[CmdletBinding()]

Param(
    [alias("Disk")] $WorkDir = 'G:\',
    [alias("Backup")] $BackDir = $Null,  # "\\backup-01.example.com\tenessee"
    [alias("Keep")] $History = 3)  # 3 Tagen im Backup-Server oder Storage-Box

$Error.Clear()

## Set a variable for computer name of the Hyper-V server. Vs
$HPV_Host = $Env:ComputerName 
$Backup_Host = 'backup-01.example.com'

$pfad = 'C:\HyperV-Backup'

## Backup Verzeichnis
# $Backup  = "\\backup-01.example.com\$HPV_Host"
if ($Null -eq $BackDir) {
    $Backup  = "\\$($Backup_Host)\$($HPV_Host)"
}
else {
    $Backup = $BackDir
}

## Logging
$LogPath = "$pfad\Logging"

# Für Email Body
$CountError = 0
$Job = "Backup job: Die Aufgabe, kopieren Daten von $HPV_Host auf $Backup"


# für SMTP-Server authentication
$SmtpServer = 'mail.example.com'
$SmtpPort = 587
$UseSsl = $True
# Auth Absender
$SmtpUser = 'monitoring@example.com'
$SmtpPwd = "$pfad\psw-storage.txt"

# Mail-Adresse
$MailFrom = $SmtpUser
$MailTo = 'cloud-support@example.com'
$MailSubject = $Null


##############################################
#####    Check Connection To Server      #####
##############################################

Function Test-ConnectionToServer {
    param (
        [string] $DirPath
    )
    # -1- Erster Versuch
    if (Test-Path -Path $DirPath) { return $True }
    else { 
        Write-Log -LogFile $LogFile -Type Info -Evt "-1- Erster Versuch: Check-Connection - $DirPath"
        Start-Sleep -Seconds 15 
    }

    # -2- Zweiter Versuch
    if (Test-Path -Path $DirPath) { return $True }
    else { 
        Write-Log -LogFile $LogFile -Type Info -Evt "-2- Zweiter Versuch: Check-Connection - $DirPath"
        Start-Sleep -Seconds 25 
    }
        
    # -3- Dritter Versuch
    if (Test-Path -Path $DirPath) { return $True }
    else { 
        Write-Log -LogFile $LogFile -Type Info -Evt "-3- Dritter Versuch: Check-Connection - $DirPath"
        Start-Sleep -Seconds 25 
    }
        
    # -4- Letzter Versuch
    if (Test-Path -Path $DirPath) { return $True }
    else { 
        Write-Log -LogFile $LogFile -Type Err -Evt "Check-Connection: $DirPath - ist nicht erreichbar"
        return $False 
    }
}

############################################################
#####    Mirror directory synchronization feature      #####
############################################################
function Synchron () {   
    param (
        [string] $sourceDirPath, 
        [string] $destDirPath, 
        [Switch] $recursive, 
        [Switch] $move, 
        [string[]] $excludSrvFoldNames
    )

    # If the specified client directory is absent, create a new directory of the same name
    if (![System.IO.Directory]::Exists($destDirPath)) {
        New-Item -Path $destDirPath -ItemType "directory" | Out-Null
    }
    # If $ NULL is passed as a filter, replace it with an array consisting of one value
    # "" (directories with this name cannot exist, and therefore this guarantees the selection 
    # of all subdirectories.
    if ($NULL -eq $excludSrvFoldNames) {
        [string[]] $excludSrvFoldNames = ""
    }

    # Get the names of the reference files
    $sourceFileNames = $NULL
    $sourceDirPath | Get-Item | Get-ChildItem | Where-Object {!$_.PSIsContainer} | ForEach-Object `
    {[string[]] $sourceFileNames += $_.PSChildName}

    # Getting the names of the target files
    if (Test-ConnectionToServer -DirPath $Backup) {
        $destFileNames = $NULL
        $destDirPath | Get-Item | Get-ChildItem | Where-Object {!$_.PSIsContainer} |
        ForEach-Object {[string[]] $destFileNames += $_.PSChildName}
    }
    else {
        Write-Log -LogFile $LogFile -Type Err -Evt "$Backup - ist nicht erreichbar"
    }

    # kopieren oder verschieben
    if ($move) {
        # Add missing files to target directory
        $info = $sourceDirPath | Get-Item | Get-ChildItem | Where-Object {!$_.PSIsContainer -and 
        !($destFileNames -contains $_.PSChildName)}

        if ($NULL -ne $info) {
            ForEach ($dd in $info) {

                if (Test-ConnectionToServer -DirPath $Backup) {
                    Move-Item -Path $dd.FullName -Destination $destDirPath -PassThru
                    Write-Log -LogFile $LogFile -Type Succ -Evt $dd.FullName
                }
                else { Write-Log -LogFile $LogFile -Type Err -Evt "$Backup - ist nicht erreichbar" 
                }

            }
        }

    }
    else  { # kopieren 
    
        # Add missing files to target directory
        $info = $sourceDirPath | Get-Item | Get-ChildItem | Where-Object {!$_.PSIsContainer -and `
        !($destFileNames -contains $_.PSChildName)}
        
        if ($NULL -ne $info) { 
            ForEach ($dd in $info) {

                if (Test-ConnectionToServer -DirPath $Backup) {
                    Copy-Item -Path $dd.FullName -Destination $destDirPath -PassThru 
                    Write-Log -LogFile $LogFile -Type Succ -Evt $dd.FullName
                }
                else { 
                    Write-Log -LogFile $LogFile -Type Err -Evt "$Backup - ist nicht erreichbar" 
                }
            }
        }

    }

    # If recursive processing is specified, then we synchronize the nested subdirectories.
    if ($recursive) {
        # Get the names of the reference subdirectories
        $sourceSubDirNames = $NULL
        $sourceDirPath | Get-Item | Get-ChildItem | Where-Object {$_.PSIsContainer -and `
        !($excludSrvFoldNames -contains $_.PSChildName)} | ForEach-Object { [string[]] $sourceSubDirNames += $_.PSChildName}

        # kopieren oder verschieben
        if ($move) {
            # Synchronizing nested subdirectories.
            $daten = $sourceDirPath | Get-Item | Get-ChildItem | Where-Object {$_.PSIsContainer -and !($excludSrvFoldNames -contains $_.PSChildName)} 
            
            if ($NULL -ne $daten) { 
                ForEach ($dd in $daten) {
                    Synchron -sourceDirPath $dd.FullName -destDirPath "$destDirPath\$($dd.PSChildName)" -recursive -move $excludSrvFoldNames
                }
            }
        }
        else {
            # Synchronizing nested subdirectories.
            $daten = $sourceDirPath | Get-Item | Get-ChildItem | Where-Object {$_.PSIsContainer -and !($excludSrvFoldNames -contains $_.PSChildName)}
            
            if ($NULL -ne $daten) { 
                ForEach ($dd in $daten) {
                    Synchron -sourceDirPath $dd.FullName -destDirPath "$destDirPath\$($dd.PSChildName)" -recursive $excludSrvFoldNames
                }
            }
        }
    }

    # Wenn leere Ordner haben, dann löschen
    if ($directory = Get-ChildItem $sourceDirPath -Recurse -Directory | ForEach-Object { if ($false -eq $_.GetFileSystemInfos()) {$_.FullName}}) {
        do { 
            Remove-Item $directory -Force -Recurse
            $directory = Get-ChildItem $sourceDirPath -Recurse -Directory | ForEach-Object { if ($false -eq $_.GetFileSystemInfos()) {$_.FullName}}
        
        } until ($null -eq $directory)

    }

} #END Function


############################################################
#####                      START!                      #####
############################################################

## If logging is configured, start logging.
## If the log file already exists, clear it.
If ($LogPath) {
    $FileName = ("HyperV-to-Storage_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
    $LogFile = "$($LogPath)\$($FileName)"

    $LogPathFolderT = Test-Path -Path $LogPath
    
    If ($LogPathFolderT -eq $False) {
        New-Item $LogPath -ItemType Directory -Force | Out-Null
        Write-Log -Type Info -Evt "Logging directory $LogFile doesn't exist. Creating it."
    }
    else {
        # Bereinigung alter Logdatei
        try {

            Clear-Log-History -LogPath $LogPath -History $History -LogFile $LogFile -ErrorAction 'Stop'
        }
        catch {
            
            Add-Content -Path $LogFile -Encoding ASCII -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") [ERROR] $($_.Exception.Message)"
        }
    }

    Add-Content -Path $LogFile -Encoding ASCII -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") [INFO] Log started"
}

############################################################
############################################################

##
## Display the current config and log if configured.
##
Write-Log -LogFile $LogFile -Type Conf -Evt "************ Running with the following config *************."
Write-Log -LogFile $LogFile -Type Conf -Evt "This virtual host:.......$HPV_Host."

Write-Log -LogFile $LogFile -Type Conf -Evt "Backup directory:........$Backup."
Write-Log -LogFile $LogFile -Type Conf -Evt "Working directory:.......$WorkDir."
If ($Null -ne $History) {
    Write-Log -LogFile $LogFile -Type Conf -Evt "Backups to keep:.........$History days"
}
else {
    Write-Log -LogFile $LogFile -Type Conf -Evt "Backups to keep:.........No Config"
}

If ($Null -ne $LogPath) {
    Write-Log -LogFile $LogFile -Type Conf -Evt "Logs directory:..........$LogPath."
}
    
else {
    Write-Log -LogFile $LogFile -Type Conf -Evt "Logs directory:..........No Config"
}
    
If ($MailTo) {
    Write-Log -LogFile $LogFile -Type Conf -Evt "E-mail log to:...........$MailTo."
}
    
else {
    Write-Log -LogFile $LogFile -Type Conf -Evt "E-mail log to:...........No Config"
}

If ($MailFrom) {
    Write-Log -LogFile $LogFile -Type Conf -Evt "E-mail log from:.........$MailFrom."
}
    
else {
    Write-Log -LogFile $LogFile -Type Conf -Evt "E-mail log from:.........No Config"
}

If ($SmtpPwd) {
    Write-Log -LogFile $LogFile -Type Conf -Evt "SMTP pwd file:...........$SmtpPwd."
}

else {
    Write-Log -LogFile $LogFile -Type Conf -Evt "SMTP pwd file:...........No Config"
}
Write-Log -LogFile $LogFile -Type Conf -Evt "**************************************************************"
Write-Log -LogFile $LogFile -Type Info -Evt "Process started."

##
## Display current config ends here.
##
if ([System.IO.Directory]::Exists($WorkDir)) {
    if ([System.IO.Directory]::Exists($Backup)) {
        Write-Log -LogFile $LogFile -Type Conf -Evt "Daten to backup:..........."
        
        ## Synchronisation
        try {
            Synchron -sourceDirPath "$WorkDir" -destDirPath "$Backup" -recursive -ErrorAction 'Stop'
        }
        catch {
            $_.Exception.Message | Write-Log -LogFile $LogFile -Type Err -Evt $_
        }

        ## allter Daten im Backup löschen
        try {
            OldDate -DirPath $Backup -keep $History -LogFile $LogFile -ErrorAction 'Stop'
        }
        catch {
            $_.Exception.Message | Write-Log -LogFile $LogFile -Type Err -Evt $_
        }
    }
    else {
        Write-Log -LogFile $LogFile -Type Err -Evt "Das Verzeichnis: $Backup fuer Backup existiert nicht!"
    }
}
else {
    Write-Log -LogFile $LogFile -Type Err -Evt "Das Verzeichnis: $WorkDir fuer VMs existiert nicht!"
}

Write-Log -LogFile $LogFile -Type Info -Evt "Process finished. Fehler waren: $CountError"

## If logging is configured then finish the log file.
If ($LogPath) {
    Add-Content -Path $LogFile -Encoding ASCII -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") [INFO] Log finished"

    ## This whole block is for e-mail, if it is configured.
    If ($SmtpServer) {
        ## Default e-mail subject if none is configured.
        If ($Null -eq $MailSubject) {
            if ($CountError -eq 0) {
                $MailSubject = "[Success]:[$HPV_Host] Storage-Backup Hyper-V Log"
            }
            else {
                $MailSubject = "[Failed]:[$HPV_Host] Storage-Backup Hyper-V Log"
            }
        }

        ## Setting the contents of the log to be the e-mail body.
        $MailBody = Get-Content -Path $LogFile | Out-String

        ## If an smtp password is configured, get the username and password together for authentication.
        ## If an smtp password is not provided then send the e-mail without authentication and obviously no SSL.
        If ($SmtpPwd -and (Test-Path -Path $SmtpPwd)) {

            ## If -ssl switch is used, send the email with SSL.
            ## If it isn't then don't use SSL, but still authenticate with the credentials.
            If ($UseSsl) {
                try {
                    EmailSenden -user $SmtpUser -to $MailTo -from $MailFrom -Subject $MailSubject -Job $Job -Fail $CountError `
                                -SSL $UseSsl -Body $MailBody -LogFile $LogFile -SmtpServer $SmtpServer -SmtpPort $SmtpPort -ErrorAction 'Stop'
                }
                catch {
                    $_.Exception.Message | Write-Log -LogFile $LogFile -Type Err -Evt $_
                }
            }
        }
        else {
            Write-Log -LogFile $LogFile -Type Err -Evt "File with password for email does not exist. Please create"
        }
    }
}

Remove-Variable -Name * -ErrorAction SilentlyContinue