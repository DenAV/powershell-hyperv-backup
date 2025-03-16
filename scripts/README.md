# Installation Script (Installation.ps1)

This PowerShell script is designed to perform the following tasks:

## Set Registry Permissions

- It retrieves the Access Control List (ACL) for a specified registry key.
- It defines an access rule that grants 'Full Control' permissions to the 'Sicherungs-Operatoren' group.
- It applies this access rule to the ACL and updates the registry key with the new ACL.

## Create Users and Add to Groups

- It prompts the user to enter a username.
- It checks if a local user with the entered username already exists.
- If the user does not exist, it prompts for a password and creates a new user with the specified username and password.
- The new user is added to the 'Sicherungs-Operatoren' group, with settings that prevent the user from changing the password and ensure the password never expires.

## Running the Script

To run this script, you should use a batch file (`start_install.bat`) with administrator rights. This ensures that the script has the necessary permissions to modify registry settings and create new users.