<#
.SYNOPSIS
    This script is used to prepare and install Backup-HPV.
.DESCRIPTION
    This script will create a registry key and set the permissions for the 'Sicherungs-Operatoren' group to 'Full Control'.
    It will also create a new user and add them to the 'Sicherungs-Operatoren' and 'Hyper-V-Administratoren' groups.
.NOTES
    File Name      : Installation.ps1
.LINK
    
.EXAMPLE
    to run the script, use start_install.bat with administrator rights.
#>



## Update Registry key
Write-Host "Update Registry key"
$registry_key = "HKLM:\SOFTWARE\Backup-HPV"

# Create the registry key if it does not exist
New-Item -Path $registry_key -Force | Out-Null

## Set Registry key to 'Full Control' for 'Sicherungs-Operatoren'
$acl = Get-Acl $registry_key

# Define the access rule for 'Sicherungs-Operatoren' group
$AccessRule = New-Object System.Security.AccessControl.RegistryAccessRule ("Sicherungs-Operatoren","FullControl","ContainerInherit,ObjectInherit", "None", "Allow")

# Apply the access rule to the ACL
$acl.SetAccessRule($AccessRule)

# Set the ACL for the registry key
$acl | Set-Acl $registry_key

# Create users and add to groups Hyper-V-Administratoren and Sicherungs-Operatoren
Write-Host "Create new backup user and add to backup groups"

# Prompt for the username
$user_name = Read-Host "Please enter the username"

# Check if the user already exists
if (Get-LocalUser -Name $user_name -ErrorAction Ignore) {
    Write-Host "The user: $user_name already exists."
}
else {
    # Prompt for the password
    $Password = Read-Host "Enter a Password" -AsSecureString

    # Define parameters for the new user
    $params = @{
        Name        = $user_name
        Password    = $Password
        Description = 'Sicherungs-Operatoren.'
        UserMayNotChangePassword = $true
        PasswordNeverExpires = $true
    }

    try {
        # Create the new user
        New-LocalUser @params

        # Add the user to the specified groups
        Add-LocalGroupMember -Group "Sicherungs-Operatoren" -Member $user_name
        Add-LocalGroupMember -Group "Hyper-V-Administratoren" -Member $user_name
    }
    catch {
        Write-Host 'Error applying special rules in one step!'
        Break
    }

    Write-Host "User: $user_name created and added to backup groups" -ForegroundColor Green
} # end else