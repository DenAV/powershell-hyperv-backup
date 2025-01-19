@Echo Off
Set bat_path=%~dp0
Set file_name=creds.ps1
powershell.exe -ExecutionPolicy ByPass -File "%bat_path%%file_name%"


