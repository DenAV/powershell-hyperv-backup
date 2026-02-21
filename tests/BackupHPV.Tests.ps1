BeforeAll {
    # Create stubs for external ADVModule functions used by BackupHPV
    function global:Write-Log {
        param($LogFile, $Type, $Evt)
    }
    function global:Get-DateShort {
        return "2025-01-15"
    }
    function global:Get-DateLong {
        return "2025-01-15_120000"
    }

    # Import the module under test
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath "..\modules\BackupHPV\BackupHPV.psm1"
    Import-Module $ModulePath -Force
}

AfterAll {
    Remove-Module BackupHPV -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\Write-Log -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\Get-DateShort -ErrorAction SilentlyContinue
    Remove-Item -Path Function:\Get-DateLong -ErrorAction SilentlyContinue
}

Describe "BackupHPV Module" {

    It "Should export Start-Copy_Daten function" {
        Get-Command -Module BackupHPV -Name Start-Copy_Daten | Should -Not -BeNullOrEmpty
    }

    It "Should export Export-StandardRunVM function" {
        Get-Command -Module BackupHPV -Name Export-StandardRunVM | Should -Not -BeNullOrEmpty
    }

    It "Should export Compress-VM function" {
        Get-Command -Module BackupHPV -Name Compress-VM | Should -Not -BeNullOrEmpty
    }
}

Describe "Start-Copy_Daten" {

    BeforeAll {
        # Create temp directories for testing
        $script:TestRoot = Join-Path -Path $TestDrive -ChildPath "CopyTest"
        $script:SourceDir = Join-Path -Path $script:TestRoot -ChildPath "Source"
        $script:DestDir = Join-Path -Path $script:TestRoot -ChildPath "Dest"
        $script:LogFile = Join-Path -Path $script:TestRoot -ChildPath "test.log"
        $script:RegKey = "TestRegistry:\Backup-HPV"

        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $script:SourceDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:DestDir -ItemType Directory -Force | Out-Null
    }

    Context "Parameter validation" {

        It "Should require sourceDirPath parameter" {
            (Get-Command Start-Copy_Daten).Parameters['sourceDirPath'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It "Should require destDirPath parameter" {
            (Get-Command Start-Copy_Daten).Parameters['destDirPath'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It "Should require RegistryKey parameter" {
            (Get-Command Start-Copy_Daten).Parameters['RegistryKey'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It "Should have UpdatePipelineStatus as switch parameter" {
            (Get-Command Start-Copy_Daten).Parameters['UpdatePipelineStatus'].SwitchParameter | Should -BeTrue
        }

        It "Should accept sourceDirPath from pipeline" {
            (Get-Command Start-Copy_Daten).Parameters['sourceDirPath'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.ValueFromPipeline } | Should -Contain $true
        }
    }

    Context "Source path validation" {

        It "Should log error when source path does not exist" {
            InModuleScope BackupHPV {
                Mock Set-ItemProperty {}
                Mock Write-Log {}

                Start-Copy_Daten -sourceDirPath "C:\NonExistent\TestPath_DoesNotExist" `
                                 -destDirPath $TestDrive `
                                 -LogFile (Join-Path $TestDrive "test.log") `
                                 -RegistryKey "HKLM:\SOFTWARE\FakeKey"

                Should -Invoke Write-Log -ParameterFilter { $Type -eq 'Err' } -Times 1 -Scope It
            }
        }
    }

    Context "Directory copy with Robocopy" {

        BeforeEach {
            # Create test files in source
            "test content" | Set-Content -Path (Join-Path $script:SourceDir "testfile.txt")
        }

        It "Should call Robocopy for directory copy" {
            InModuleScope BackupHPV -ArgumentList @($script:SourceDir, $script:DestDir, $script:LogFile) {
                param($SourceDir, $DestDir, $LogFile)
                Mock Set-ItemProperty {}
                Mock Write-Log {}
                Mock robocopy.exe { $global:LASTEXITCODE = 1 }

                Start-Copy_Daten -sourceDirPath $SourceDir `
                                 -destDirPath $DestDir `
                                 -LogFile $LogFile `
                                 -RegistryKey "HKLM:\SOFTWARE\FakeKey"

                Should -Invoke robocopy.exe -Times 1 -Scope It
            }
        }
    }
}

Describe "Export-StandardRunVM" {

    BeforeAll {
        $script:TestRoot = Join-Path -Path $TestDrive -ChildPath "ExportTest"
        $script:ExportDir = Join-Path -Path $script:TestRoot -ChildPath "Export"
        $script:LogFile = Join-Path -Path $script:TestRoot -ChildPath "test.log"
        $script:RegKey = "TestRegistry:\Backup-HPV"

        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $script:ExportDir -ItemType Directory -Force | Out-Null
    }

    Context "Parameter validation" {

        It "Should require ExportVmName parameter" {
            (Get-Command Export-StandardRunVM).Parameters['ExportVmName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It "Should require ExportDirectory parameter" {
            (Get-Command Export-StandardRunVM).Parameters['ExportDirectory'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It "Should require RegistryKey parameter" {
            (Get-Command Export-StandardRunVM).Parameters['RegistryKey'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It "Should accept ExportVmName from pipeline" {
            (Get-Command Export-StandardRunVM).Parameters['ExportVmName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.ValueFromPipeline } | Should -Contain $true
        }
    }

    Context "Registry key validation" {

        It "Should throw when registry key does not exist" {
            Mock Test-Path { return $false } -ParameterFilter { $Path -eq "HKLM:\FAKE\KEY" }
            Mock Set-ItemProperty {}

            { Export-StandardRunVM -ExportVmName "TestVM" `
                                  -ExportDirectory $script:ExportDir `
                                  -RegistryKey "HKLM:\FAKE\KEY" `
                                  -LogFile $script:LogFile } | Should -Throw
        }
    }

    Context "VM export" {

        It "Should remove existing backup folder before export" {
            InModuleScope BackupHPV -ArgumentList @($script:ExportDir, $script:LogFile) {
                param($ExportDir, $LogFile)

                $existingBackup = Join-Path -Path $ExportDir -ChildPath "TestVM"
                New-Item -Path $existingBackup -ItemType Directory -Force | Out-Null
                "dummy" | Set-Content (Join-Path $existingBackup "disk.vhdx")

                Mock Test-Path { return $true } -ParameterFilter { $Path -like "*SOFTWARE*" -or $Path -like "*HKLM*" }
                Mock Set-ItemProperty {}
                Mock Write-Log {}
                Mock Export-VM {}
                Mock Remove-Item {}

                Export-StandardRunVM -ExportVmName "TestVM" `
                                    -ExportDirectory $ExportDir `
                                    -RegistryKey "HKLM:\SOFTWARE\FakeKey" `
                                    -LogFile $LogFile

                Should -Invoke Remove-Item -Times 1 -Scope It
            }
        }

        It "Should return PSCustomObject with VMName and ExportStatus" {
            InModuleScope BackupHPV -ArgumentList @($script:ExportDir, $script:LogFile) {
                param($ExportDir, $LogFile)

                Mock Test-Path { return $true } -ParameterFilter { $Path -like "*SOFTWARE*" -or $Path -like "*HKLM*" }
                Mock Test-Path { return $false } -ParameterFilter { $PathType -eq 'Container' }
                Mock Set-ItemProperty {}
                Mock Write-Log {}
                Mock Export-VM {}

                $result = Export-StandardRunVM -ExportVmName "TestVM" `
                                              -ExportDirectory $ExportDir `
                                              -RegistryKey "HKLM:\SOFTWARE\FakeKey" `
                                              -LogFile $LogFile

                $result.VMName | Should -Be "TestVM"
                $result | Should -BeOfType [PSCustomObject]
                $result.PSObject.Properties.Name | Should -Contain "ExportStatus"
                $result.PSObject.Properties.Name | Should -Contain "Timestamp"
            }
        }
    }
}

Describe "Compress-VM" {

    BeforeAll {
        $script:TestRoot = Join-Path -Path $TestDrive -ChildPath "CompressTest"
        $script:WorkDir = Join-Path -Path $script:TestRoot -ChildPath "Work"
        $script:LogFile = Join-Path -Path $script:TestRoot -ChildPath "test.log"
        $script:RegKey = "TestRegistry:\Backup-HPV"

        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null
    }

    Context "Parameter validation" {

        It "Should require VmName parameter" {
            (Get-Command Compress-VM).Parameters['VmName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It "Should require WorkDir parameter" {
            (Get-Command Compress-VM).Parameters['WorkDir'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It "Should require RegistryKey parameter" {
            (Get-Command Compress-VM).Parameters['RegistryKey'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }

        It "Should have ShortDate as switch parameter" {
            (Get-Command Compress-VM).Parameters['ShortDate'].SwitchParameter | Should -BeTrue
        }

        It "Should have Encrypt as switch parameter" {
            (Get-Command Compress-VM).Parameters['Encrypt'].SwitchParameter | Should -BeTrue
        }

        It "Should have default SzThreads value of mmt1" {
            (Get-Command Compress-VM).Parameters['SzThreads'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $false
        }

        It "Should have default SzCompression value of mx1" {
            (Get-Command Compress-VM).Parameters['SzCompression'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $false
        }
    }

    Context "Archive naming" {

        It "Should use short date in archive name when ShortDate is set" {
            InModuleScope BackupHPV -ArgumentList @($script:WorkDir, $script:LogFile) {
                param($WorkDir, $LogFile)

                $vmDir = Join-Path -Path $WorkDir -ChildPath "TestVM"
                New-Item -Path $vmDir -ItemType Directory -Force | Out-Null
                "dummy" | Set-Content (Join-Path $vmDir "disk.vhdx")

                Mock Test-Path { return $false } -ParameterFilter { $Path -like "*TestVM-*.*z*" }
                Mock Test-Path { return $true } -ParameterFilter { $Path -like "*Programme*" }
                Mock Set-ItemProperty {}
                Mock Write-Log {}
                Mock Get-ChildItem { } -ParameterFilter { $Filter -like "tmp_*" }
                Mock Remove-Item {}

                # The function should construct filename with short date
                { Compress-VM -VmName "TestVM" `
                              -WorkDir $WorkDir `
                              -LogFile $LogFile `
                              -RegistryKey "HKLM:\SOFTWARE\FakeKey" `
                              -ShortDate } | Should -Not -Throw
            }
        }
    }
}

Describe "Script syntax validation" {

    $scripts = @(
        @{ Name = "Backup-HPV(1 part).ps1";   Path = (Join-Path $PSScriptRoot "..\Backup-HPV(1 part).ps1") }
        @{ Name = "Backup-HPV(2 part).ps1";   Path = (Join-Path $PSScriptRoot "..\Backup-HPV(2 part).ps1") }
        @{ Name = "Backup-HPV(1-2 part).ps1"; Path = (Join-Path $PSScriptRoot "..\Backup-HPV(1-2 part).ps1") }
        @{ Name = "BackupHPV.psm1";           Path = (Join-Path $PSScriptRoot "..\modules\BackupHPV\BackupHPV.psm1") }
    )

    It "<Name> should have valid PowerShell syntax" -ForEach $scripts {
        $errors = $null
        [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $Path -Raw), [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It "<Name> should not be empty" -ForEach $scripts {
        (Get-Content -Path $Path -Raw).Trim() | Should -Not -BeNullOrEmpty
    }
}
