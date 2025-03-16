# HyperV-Backup Setup Guide

## Prerequisites

1. Ensure you have administrative privileges on the Hyper-V host machine.
2. Install the Hyper-V PowerShell management modules.

## Setup Instructions

1. **Create a User:**
   - Create a user and add them to the "Hyper-V Administrators" and "Backup Operators" groups.

2. **Clone the Repository:**
   - Clone the repository from [https://github.com/DenAV/powershell-hyperv-backup.git](https://github.com/DenAV/powershell-hyperv-backup.git) into a folder, e.g., `C:\Scripts`.

3. **Copy Script Contents:**
   - Copy the contents of the `HyperV-Backup` folder to `C:\Scripts\HyperV-Backup`.

4. **Run Installation Script:**
   - Run the `start_install.bat` script as an administrator from the `C:\Scripts\HyperV-Backup\Installation` directory.

5. **Import Task Scheduler Tasks:**
   - Open Task Scheduler.
   - Import the tasks `Backup-HPV part1 (Daily)` and `Backup-HPV part2 (Daily)` from the `C:\Scripts\HyperV-Backup\Task-Schedule` directory.
   - Assign the created user to run these tasks.

6. **Configure `backup-hpv.ini`:**
   - Edit the `backup-hpv.ini` file located in `C:\Scripts\HyperV-Backup` to configure your backup settings.

7. **Install Required Module:**
   - Ensure the `ADVModule.psm1` module is installed.

8. **Create Credentials:**
   - Run the `creds_start.bat` script from the `C:\Scripts\HyperV-Backup\Credential` directory.
   - Enter the credentials for `backup-server@example.com`.

## Additional Configuration

- **Logging:**
  - Ensure the logging directory is set up correctly in the `backup-hpv.ini` file.

- **Email Notifications:**
  - Configure the SMTP server details in the `backup-hpv.ini` file for email notifications.

## Running the Backup

- The backup tasks will run daily as per the Task Scheduler configuration.
- Logs and backup results will be stored as configured in the `backup-hpv.ini` file.

For detailed instructions, refer to the [Installation README](Installation/README.md).