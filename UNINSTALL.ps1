# Dataverse Impersonator - Uninstaller
# Removes the per-user protocol registration and all files installed under
# %LOCALAPPDATA%\DataverseImpersonator. If the installer changed CurrentUser from
# AllSigned/Undefined to RemoteSigned, this script can offer to restore the previous value.

& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Add-Type -AssemblyName System.Windows.Forms

    $installRoot = Join-Path $env:LOCALAPPDATA 'DataverseImpersonator'
    $statePath = Join-Path $installRoot 'Install-State.json'
    $protocolKey = 'HKCU:\Software\Classes\dataverseimpersonator'

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Uninstall Dataverse Impersonator for the current Windows user?`r`n`r`n" +
        "This will remove:`r`n" +
        "- the dataverseimpersonator: custom protocol`r`n" +
        "- the installed runtime and hidden launcher`r`n" +
        "- Bookmarklet.txt`r`n" +
        "- isolated WebView2 session folders created under the install directory`r`n`r`n" +
        "It does not change Dataverse or delete the Edge favorite itself.",
        'Dataverse Impersonator - Uninstall',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $installState = $null
    if (Test-Path -LiteralPath $statePath) {
        try {
            $installState = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $installState = $null
        }
    }

    if (Test-Path -LiteralPath $protocolKey) {
        Remove-Item -LiteralPath $protocolKey -Recurse -Force
    }

    if (Test-Path -LiteralPath $installRoot) {
        Remove-Item -LiteralPath $installRoot -Recurse -Force
    }

    $policyResult = 'Execution policy was not changed.'

    if ($installState -and $installState.InstallerChangedCurrentUserExecutionPolicy -eq $true) {
        $previousPolicy = [string]$installState.PreviousCurrentUserExecutionPolicy
        if ([string]::IsNullOrWhiteSpace($previousPolicy)) {
            $previousPolicy = 'Undefined'
        }

        $currentPolicy = [string](Get-ExecutionPolicy -Scope CurrentUser)
        $restore = [System.Windows.Forms.MessageBox]::Show(
            "The Dataverse Impersonator installer previously changed the CurrentUser execution policy so its locally-installed unsigned runtime could launch.`r`n`r`n" +
            "CurrentUser now: $currentPolicy`r`n" +
            "Previous CurrentUser value: $previousPolicy`r`n`r`n" +
            "Restore the previous CurrentUser execution-policy value now?",
            'Dataverse Impersonator - Restore execution policy?',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($restore -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy $previousPolicy -Force -ErrorAction Stop
                $policyResult = "CurrentUser execution policy was restored to $previousPolicy. Effective policy is now $([string](Get-ExecutionPolicy))."
            }
            catch {
                $policyResult = "The application was removed, but the execution policy could not be restored: $($_.Exception.Message)"
            }
        }
        else {
            $policyResult = "CurrentUser execution policy was left at $currentPolicy."
        }
    }

    Write-Host ''
    Write-Host 'Dataverse Impersonator uninstalled for the current Windows user.' -ForegroundColor Green
    Write-Host $policyResult
    Write-Host 'If an Edge favorite named Impersonate Here still exists, delete it manually.' -ForegroundColor Yellow

    [System.Windows.Forms.MessageBox]::Show(
        "Dataverse Impersonator was removed for the current Windows user.`r`n`r`n" +
        $policyResult + "`r`n`r`n" +
        "If the Edge favorite named Impersonate Here still exists, delete it manually.",
        'Dataverse Impersonator - Uninstall complete',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}
