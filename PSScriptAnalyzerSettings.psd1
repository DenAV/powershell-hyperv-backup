@{
    # PSScriptAnalyzer settings for powershell-hyperv-backup
    # https://github.com/PowerShell/PSScriptAnalyzer

    Severity = @('Error', 'Warning')

    # Rules to exclude (incompatible with legacy code patterns)
    ExcludeRules = @(
        # Allow Write-Host usage in scripts (used for console output)
        'PSAvoidUsingWriteHost',
        # Allow positional parameters in legacy scripts
        'PSAvoidUsingPositionalParameters',
        # Allow ConvertTo-SecureString with plaintext (used for stored credentials)
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        # Suppress ShouldProcess requirement for existing functions
        'PSUseShouldProcessForStateChangingFunctions',
        # Cosmetic rules — disabled for now, will be enabled after code cleanup
        'PSPlaceOpenBrace',
        'PSPlaceCloseBrace',
        'PSUseConsistentWhitespace',
        # Switch default values are used intentionally (e.g. $Encrypt = $True)
        'PSAvoidDefaultValueSwitchParameter',
        # Legacy scripts have parameters consumed by called functions
        'PSReviewUnusedParameter',
        # BOM encoding — not enforced for cross-platform compatibility
        'PSUseBOMForUnicodeEncodedFile',
        # Vars assigned but used in downstream scripts (dot-sourced)
        'PSUseDeclaredVarsMoreThanAssignments',
        # Test stubs intentionally override built-in cmdlets
        'PSAvoidOverwritingBuiltInCmdlets'
    )

    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
