    
# Ordner, in dem das Script liegt ermitteln
$path = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)

$creds = Get-Credential
$creds.Password | ConvertFrom-SecureString | Set-Content "$path\pwd-storage.txt"