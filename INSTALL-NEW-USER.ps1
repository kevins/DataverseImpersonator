# Dataverse Impersonator - New User Installer
# Run this once per Windows user. It installs the runtime locally, registers the
# dataverseimpersonator: protocol, creates a hidden launcher, and prepares the bookmarklet.
# If PowerShell is effectively AllSigned, the installer can offer to set CurrentUser
# to RemoteSigned so the locally-created unsigned runtime can launch from the bookmarklet.

& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Add-Type -AssemblyName System.Windows.Forms

    $installRoot = Join-Path $env:LOCALAPPDATA 'DataverseImpersonator'
    $installedScriptPath = Join-Path $installRoot 'Dataverse-Impersonator.ps1'
    $launcherPath = Join-Path $installRoot 'Launch-Dataverse-Impersonator.vbs'
    $bookmarkletPath = Join-Path $installRoot 'Bookmarklet.txt'
    $statePath = Join-Path $installRoot 'Install-State.json'
    $protocolName = 'dataverseimpersonator'

    $runtimePayload = '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'

    function Get-PolicySnapshot {
        $snapshot = [ordered]@{}
        foreach ($entry in (Get-ExecutionPolicy -List)) {
            $snapshot[[string]$entry.Scope] = [string]$entry.ExecutionPolicy
        }
        return $snapshot
    }

    function Format-PolicySnapshot {
        param([Parameter(Mandatory = $true)]$Snapshot)

        $lines = @()
        foreach ($scope in @('MachinePolicy', 'UserPolicy', 'Process', 'CurrentUser', 'LocalMachine')) {
            if ($Snapshot.Contains($scope)) {
                $lines += ('{0}: {1}' -f $scope, $Snapshot[$scope])
            }
        }
        return ($lines -join "`r`n")
    }

    $existingState = $null
    if (Test-Path -LiteralPath $statePath) {
        try {
            $existingState = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $existingState = $null
        }
    }

    $policyBefore = Get-PolicySnapshot
    $effectivePolicyBefore = [string](Get-ExecutionPolicy)
    $currentUserPolicyBefore = [string](Get-ExecutionPolicy -Scope CurrentUser)
    $policyChangedThisRun = $false

    $installerPreviouslyChangedPolicy = $false
    $originalCurrentUserPolicy = $currentUserPolicyBefore

    if ($existingState -and $existingState.InstallerChangedCurrentUserExecutionPolicy -eq $true) {
        $installerPreviouslyChangedPolicy = $true
        if (-not [string]::IsNullOrWhiteSpace([string]$existingState.PreviousCurrentUserExecutionPolicy)) {
            $originalCurrentUserPolicy = [string]$existingState.PreviousCurrentUserExecutionPolicy
        }
    }

    if ($effectivePolicyBefore -eq 'AllSigned') {
        $policyText = Format-PolicySnapshot -Snapshot $policyBefore
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "PowerShell is currently using the AllSigned execution policy.`r`n`r`n" +
            "The bookmarklet launches a locally-installed Dataverse-Impersonator.ps1 file. " +
            "Because that file is not digitally signed, AllSigned would block it and the bookmarklet would appear to do nothing.`r`n`r`n" +
            "Would you like this installer to set the PowerShell execution policy for YOUR WINDOWS ACCOUNT only to RemoteSigned?`r`n`r`n" +
            "What changes:`r`n" +
            "- CurrentUser becomes RemoteSigned.`r`n" +
            "- The machine-wide LocalMachine setting is not changed.`r`n" +
            "- Locally-created scripts can run unsigned.`r`n" +
            "- Scripts marked as downloaded from the Internet still require a trusted signature unless explicitly unblocked.`r`n`r`n" +
            "The installer records the previous CurrentUser setting so UNINSTALL.ps1 can offer to restore it later.`r`n`r`n" +
            "Current policy:`r`n" + $policyText,
            'Dataverse Impersonator - AllSigned detected',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            [System.Windows.Forms.MessageBox]::Show(
                "Installation was cancelled.`r`n`r`n" +
                "Nothing needs to be installed until the bookmarklet runtime can be launched. " +
                "You can rerun this installer and accept the RemoteSigned CurrentUser option, or use a runtime signed by a trusted code-signing certificate.",
                'Dataverse Impersonator - Installation cancelled',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        try {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
            $policyChangedThisRun = $true
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not set CurrentUser to RemoteSigned.`r`n`r`n" + $_.Exception.Message,
                'Dataverse Impersonator - Execution policy change failed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }

        $effectiveAfterChange = [string](Get-ExecutionPolicy)
        if ($effectiveAfterChange -eq 'AllSigned') {
            try {
                Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy $currentUserPolicyBefore -Force -ErrorAction SilentlyContinue
            }
            catch {
            }

            $policyAfterFailedChange = Get-PolicySnapshot
            [System.Windows.Forms.MessageBox]::Show(
                "CurrentUser was changed, but AllSigned is still the effective policy. " +
                "A higher-precedence policy is enforcing AllSigned, so this installer cannot make the unsigned runtime launch automatically.`r`n`r`n" +
                "No application files were installed.`r`n`r`n" +
                (Format-PolicySnapshot -Snapshot $policyAfterFailedChange),
                'Dataverse Impersonator - AllSigned is enforced',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }
    }
    elseif ($effectivePolicyBefore -eq 'Restricted') {
        [System.Windows.Forms.MessageBox]::Show(
            "PowerShell's effective execution policy is Restricted. The bookmarklet runtime cannot be launched as a .ps1 file under this policy.`r`n`r`n" +
            "This installer only offers an automatic CurrentUser fix when AllSigned is detected. Installation has been cancelled.",
            'Dataverse Impersonator - Restricted execution policy',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    $payloadBytes = [Convert]::FromBase64String($runtimePayload)
    $compressedStream = New-Object IO.MemoryStream(,$payloadBytes)
    try {
        $gzip = New-Object IO.Compression.GZipStream($compressedStream, [IO.Compression.CompressionMode]::Decompress)
        try {
            $reader = New-Object IO.StreamReader($gzip, [Text.Encoding]::UTF8)
            try {
                $runtimeSource = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $gzip.Dispose()
        }
    }
    finally {
        $compressedStream.Dispose()
    }

    if ([string]::IsNullOrWhiteSpace($runtimeSource) -or
        -not $runtimeSource.Contains('# Dataverse Impersonator') -or
        -not $runtimeSource.Contains('DataverseImpersonatorFormTemplate')) {
        throw 'The embedded Dataverse Impersonator runtime could not be validated.'
    }

    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null

    $policyManagedByInstaller = $installerPreviouslyChangedPolicy -or $policyChangedThisRun
    $state = [ordered]@{
        InstallerChangedCurrentUserExecutionPolicy = $policyManagedByInstaller
        PreviousCurrentUserExecutionPolicy = $originalCurrentUserPolicy
        CurrentUserExecutionPolicyAfterInstall = [string](Get-ExecutionPolicy -Scope CurrentUser)
        EffectiveExecutionPolicyAfterInstall = [string](Get-ExecutionPolicy)
        InstalledUtc = [DateTime]::UtcNow.ToString('o')
    }

    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 4), $utf8NoBom)
    [IO.File]::WriteAllText($installedScriptPath, $runtimeSource, $utf8NoBom)
    Unblock-File -LiteralPath $installedScriptPath -ErrorAction SilentlyContinue

    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $powershellExe)) {
        $powershellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
    }

    $wscriptExe = Join-Path $env:WINDIR 'System32\wscript.exe'
    if (-not (Test-Path -LiteralPath $wscriptExe)) {
        $wscriptExe = (Get-Command wscript.exe -ErrorAction Stop).Source
    }

    $launcher = @'
Option Explicit

Dim uri, psPath, scriptPath, command
Dim shell, processEnvironment

If WScript.Arguments.Count < 1 Then
    WScript.Quit 1
End If

uri = WScript.Arguments(0)

If InStr(uri, Chr(34)) > 0 Then
    WScript.Quit 2
End If

psPath = "__POWERSHELL__"
scriptPath = "__SCRIPT__"

Set shell = CreateObject("WScript.Shell")
Set processEnvironment = shell.Environment("PROCESS")
processEnvironment("DATAVERSE_IMPERSONATOR_LAUNCH_URI") = uri

command = Chr(34) & psPath & Chr(34) & _
          " -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -File " & _
          Chr(34) & scriptPath & Chr(34)

shell.Run command, 0, False
'@

    $launcher = $launcher.Replace('__POWERSHELL__', $powershellExe).Replace('__SCRIPT__', $installedScriptPath)
    [IO.File]::WriteAllText($launcherPath, $launcher, [Text.Encoding]::Unicode)

    $protocolKey = "HKCU:\Software\Classes\$protocolName"
    $commandKey = Join-Path $protocolKey 'shell\open\command'

    New-Item -Path $protocolKey -Force | Out-Null
    Set-Item -Path $protocolKey -Value 'URL:Dataverse Impersonator Protocol'
    New-ItemProperty -Path $protocolKey -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null

    New-Item -Path $commandKey -Force | Out-Null
    $command = '"{0}" "{1}" "%1"' -f $wscriptExe, $launcherPath
    Set-Item -Path $commandKey -Value $command

    $bookmarklet = "javascript:(()=>{if(!/(^|\.)dynamics\.com$/i.test(location.hostname)){alert('Open a Dataverse model-driven app first.');return;}const u='dataverseimpersonator:open?url='+encodeURIComponent(location.href);const a=document.createElement('a');a.href=u;a.style.display='none';document.body.appendChild(a);a.click();a.remove()})()"
    [IO.File]::WriteAllText($bookmarkletPath, $bookmarklet, $utf8NoBom)

    if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
        $bookmarklet | Set-Clipboard
    }

    $policyMessage = ''
    if ($policyChangedThisRun) {
        $policyMessage = "`r`n`r`nPowerShell CurrentUser execution policy was changed from $currentUserPolicyBefore to RemoteSigned so the locally-installed runtime can launch. UNINSTALL.ps1 can offer to restore the previous setting."
    }
    elseif ($installerPreviouslyChangedPolicy) {
        $policyMessage = "`r`n`r`nThis installation is still using the CurrentUser RemoteSigned setting previously created by this installer. UNINSTALL.ps1 can offer to restore the original setting."
    }

    Write-Host ''
    Write-Host 'Dataverse Impersonator installed successfully.' -ForegroundColor Green
    Write-Host "Installed runtime: $installedScriptPath"
    Write-Host "Hidden launcher: $launcherPath"
    Write-Host "Bookmarklet text: $bookmarkletPath"
    Write-Host "Effective execution policy: $([string](Get-ExecutionPolicy))"
    Write-Host ''
    Write-Host 'Create an Edge favorite named: Impersonate Here' -ForegroundColor Yellow
    Write-Host 'Paste the bookmarklet text into the favorite URL field.' -ForegroundColor Yellow

    [System.Windows.Forms.MessageBox]::Show(
        "Dataverse Impersonator installed successfully.`r`n`r`n" +
        "What was installed:`r`n" +
        "- Runtime: $installedScriptPath`r`n" +
        "- Hidden launcher: $launcherPath`r`n" +
        "- Custom protocol: dataverseimpersonator:`r`n" +
        "- Bookmarklet: $bookmarkletPath`r`n`r`n" +
        "Next:`r`n1. Create an Edge favorite named Impersonate Here.`r`n" +
        "2. Paste the bookmarklet text into the favorite URL field.`r`n" +
        "3. Open a Dataverse model-driven app and click the favorite.`r`n" +
        "4. If Edge asks permission to open Dataverse Impersonator, allow it.`r`n`r`n" +
        "The bookmarklet was also copied to the clipboard when Set-Clipboard was available." +
        $policyMessage,
        'Dataverse Impersonator - Installation complete',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}
