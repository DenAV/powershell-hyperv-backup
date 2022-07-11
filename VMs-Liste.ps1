<#PSScriptInfo
.SYNOPSIS
Skript - Creates a list of VMs and divides it into the specified number of parts
.VERSION 2021-05-19

.AUTHOR Denis Denk
#>

$Error.Clear()

$vms_path = 'C:\HyperV-Backup\Liste'
$vms_list = "vms_list.txt"

# Prüfung Verzeichnis für Backup
if ([System.IO.Directory]::Exists($vms_path)) {
    # neu VMs Liste
    try {
        Get-VM | Where-Object {$_.State -eq "Running"} | Select-Object -ExpandProperty Name | Set-Content -Force -Path "$vms_path\$vms_list" -ErrorAction 'Stop'
    }
    catch {
        $_.Exception.Message
    }
    
    $lineCount = 1
    $fileCount = 0
    
    if([System.IO.File]::Exists("$vms_path\$vms_list")) {
        $file = get-content "$vms_path\$vms_list"
        $parts = 2.5 #Anzahl Datensätze
        $maxLines = [math]::Round($file.Length/$parts) 
        
        # Delete alte Dateien
        Get-ChildItem -Path $vms_path -Filter vms_?.txt | Remove-Item -ErrorAction Ignore
        
        foreach ( $linie in get-content $vms_path\$vms_list) {

            Write-Output $linie | out-file -Append "$vms_path\vms_$fileCount.txt"
            
            $lineCount++
                
            if ($lineCount -eq $maxLines) {
                $fileCount++
                $lineCount = 1
            }
        }
    }
    else {
        write-host "Die Datei: $vms_path\$vms_list existiert nicht!"
    }
}
else {
    write-host "Das Verzeichnis: $vms_path fuer $vms_list existiert nicht!"
}

Remove-Variable -Name * -ErrorAction SilentlyContinue
