# Credential Management Script

This guide will help you understand how to use the `creds.ps1` script for managing credentials in your PowerShell Hyper-V backup setup.

## Prerequisites

- PowerShell 5.1 or later

## Usage

1. **Run the Script**:
- To run the script, use creds_start.bat with admin rights.

2. **Follow the Prompts**: The script will prompt you to enter the necessary credentials. Make sure to provide accurate information.

## Example

## Troubleshooting

- **Execution Policy**: If you encounter an execution policy error, you may need to set the policy to allow script execution:
    ```powershell
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```

- **Permission Issues**: Ensure you are running PowerShell as an administrator.

## Additional Resources

- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
