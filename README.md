# Dataverse Impersonator

A Windows PowerShell/WebView2 utility for testing a Dataverse model-driven app under another user's Dataverse security context.

## Read this first

There are **three PowerShell files**, and each has a different job:

- **`Dataverse-Impersonator.ps1`** — the application itself. Run it manually and it immediately asks for the Dataverse/model-driven-app URL. It does **not** install or update the bookmarklet.
- **`INSTALL-NEW-USER.ps1`** — one-time setup for a user who wants the Edge bookmarklet. It installs a local runtime, hidden launcher, bookmarklet text, and the per-user `dataverseimpersonator:` Windows protocol.
- **`UNINSTALL.ps1`** — removes the installed runtime, launcher, protocol registration, bookmarklet file, and local WebView2 session data.

### Important: `AllSigned` PowerShell environments

The bookmarklet eventually launches a locally-created `Dataverse-Impersonator.ps1` file. If PowerShell's **effective execution policy is `AllSigned`**, an unsigned runtime is blocked and the bookmarklet appears to do nothing.

`INSTALL-NEW-USER.ps1` checks this **before installing**. If it detects `AllSigned`, it displays a confirmation explaining the change and offers to set:

```text
CurrentUser = RemoteSigned
```

This changes the policy for **that Windows account only**. It does not modify the machine-wide `LocalMachine` setting. Under `RemoteSigned`, locally-created scripts can run unsigned, while scripts marked as downloaded from the Internet still require a trusted signature unless they are explicitly unblocked.

The installer never changes this silently. If the user chooses **No**, installation is cancelled. If the user chooses **Yes**, the installer records the previous `CurrentUser` value in `%LOCALAPPDATA%\DataverseImpersonator\Install-State.json`. `UNINSTALL.ps1` can later offer to restore that previous value.

If `AllSigned` remains effective after changing `CurrentUser` — for example because a higher-precedence organizational policy enforces it — the installer restores the attempted CurrentUser change, stops, and explains that a trusted code-signed runtime is required.

## New-user installation

On a locked-down machine, the safest workflow is to **copy/paste the installer source into PowerShell ISE** rather than double-clicking or directly running the downloaded unsigned `.ps1`.

1. Open `INSTALL-NEW-USER.ps1` as text.
2. Press **Ctrl+A**, then **Ctrl+C**.
3. Open **Windows PowerShell ISE**.
4. Paste into a new Script Pane.
5. Press **F5**.
6. If an **AllSigned detected** dialog appears, read the explanation and choose whether to set `CurrentUser` to `RemoteSigned`.
7. After installation, create an Edge favorite named **Impersonate Here**.
8. Paste the contents of `%LOCALAPPDATA%\DataverseImpersonator\Bookmarklet.txt` into the favorite's URL field. The installer also copies this value to the clipboard when `Set-Clipboard` is available.

The installer writes:

```text
%LOCALAPPDATA%\DataverseImpersonator\Dataverse-Impersonator.ps1
%LOCALAPPDATA%\DataverseImpersonator\Launch-Dataverse-Impersonator.vbs
%LOCALAPPDATA%\DataverseImpersonator\Bookmarklet.txt
%LOCALAPPDATA%\DataverseImpersonator\Install-State.json
```

It also registers the per-user custom protocol under:

```text
HKEY_CURRENT_USER\Software\Classes\dataverseimpersonator
```

No browser extension is installed and administrator rights are normally not required.

## How the bookmarklet works

After installation, clicking **Impersonate Here** on a Dataverse model-driven-app page performs this handoff:

```text
Current Edge model-driven app page
             |
             | bookmarklet captures location.href
             v
dataverseimpersonator:open?url=<encoded current page URL>
             |
             | per-user Windows protocol registration
             v
Hidden VBS launcher
             |
             | puts the launch URI in a temporary PROCESS environment variable
             | and starts PowerShell hidden
             v
%LOCALAPPDATA%\DataverseImpersonator\Dataverse-Impersonator.ps1
             |
             v
Dataverse Impersonator opens the exact record/view/dashboard/page
```

The bookmarklet uses `dataverseimpersonator:open?...` **without `//`**. Keep the bookmarklet exactly as provided.

On first use, Edge/Windows can show an external-protocol confirmation. Choose **Open** / **Allow**. If an **Always allow/open** option is offered and permitted by your organization, it can be selected for one-click launches later.

## Manual application use

`Dataverse-Impersonator.ps1` is only the application runtime.

1. Open it in PowerShell ISE, or copy/paste the complete source into a new ISE Script Pane.
2. Press **F5**.
3. The first prompt asks for the full `https://...dynamics.com/...` URL of the model-driven app/environment.
4. Paste the URL and continue.

It does **not** ask whether a bookmarklet should be installed and does not change Windows configuration.

## Uninstall / clean reinstall

To remove everything installed by the bookmarklet setup:

1. Close any open Dataverse Impersonator windows.
2. Open `UNINSTALL.ps1` as text.
3. Copy/paste the full source into PowerShell ISE.
4. Press **F5**.
5. Confirm the uninstall.
6. If the installer previously changed `CurrentUser` to `RemoteSigned`, the uninstaller will offer to restore the previous CurrentUser value.
7. Delete the **Impersonate Here** Edge favorite manually if you no longer want it.

For a clean test of the `AllSigned` flow, choose **Yes** when the uninstaller offers to restore the previous execution-policy setting, then run `INSTALL-NEW-USER.ps1` again. If the effective policy returns to `AllSigned`, the installer should display the new AllSigned explanation/fix dialog.

## Updating an installed copy

Run the newest `INSTALL-NEW-USER.ps1` again. It replaces the installed runtime and hidden launcher, rewrites `Bookmarklet.txt`, refreshes the per-user protocol registration, and preserves the original execution-policy value if a previous installer run changed it.

Then update the Edge favorite with the newest `Bookmarklet.txt` value if it changed.

## Repository files

```text
Dataverse-Impersonator.ps1
INSTALL-NEW-USER.ps1
UNINSTALL.ps1
Bookmarklet.txt
README.md
```

## What it does

Dataverse Impersonator opens a model-driven app in WebView2 and applies the Dataverse `CallerObjectId` impersonation header to Web API requests for the current Dataverse host.

Features include:

- search Dataverse users by name or email;
- impersonate Entra-backed users using `CallerObjectId`;
- verify that the signed-in caller has `prvActOnBehalfOfAnotherUser`;
- detect disabled Dataverse users;
- detect disabled business units;
- block users that do not have a Microsoft Entra object ID;
- check whether a user has access to the current model-driven app;
- stop impersonating and return to the real signed-in user;
- open the exact current record, view, dashboard, or page from the bookmarklet;
- Back, Forward, Refresh, URL, and Copy URL controls;
- run multiple isolated impersonator windows at the same time;
- launch from the bookmarklet without leaving a PowerShell console visible.

> **Important:** this is a real Dataverse session, not a read-only simulator. Actions performed while impersonating can change real records. Use a development/test environment whenever possible.

## PowerShell 5.1 compatibility

The source files are kept UTF-8 without a BOM so they can be copied directly into PowerShell ISE. Browser navigation symbols are represented with Unicode escape sequences in the embedded C# code, so the installed runtime renders the Back, Forward, and Refresh icons correctly even though Windows PowerShell 5.1 treats BOM-less script files as the legacy system encoding.

## Requirements

- Windows PowerShell 5.1
- PowerShell ISE for the recommended copy/paste workflow
- Microsoft Edge WebView2 Runtime
- Microsoft WebView2 SDK DLLs
- access to the target Dataverse environment
- `prvActOnBehalfOfAnotherUser` assigned directly to the person running the tool
- the target Dataverse user must be enabled
- the target user's business unit must be enabled
- the target Dataverse user must have a Microsoft Entra object ID
- the target user must be able to access the model-driven app being opened

The WebView2 SDK files required are:

```text
Microsoft.Web.WebView2.Core.dll
Microsoft.Web.WebView2.WinForms.dll
WebView2Loader.dll
```

The runtime looks for them in the script folder, common Microsoft Office locations, the user's Microsoft.Web.WebView2 NuGet cache, and `WEBVIEW2_SDK_PATH`.

## Required Dataverse privilege

The caller needs:

```text
prvActOnBehalfOfAnotherUser
```

The built-in **Delegate** security role contains this privilege.

Microsoft documentation:

- [Impersonate another user using the Dataverse Web API](https://learn.microsoft.com/power-apps/developer/data-platform/webapi/impersonate-another-user-web-api)
- [Impersonate another user in Microsoft Dataverse](https://learn.microsoft.com/power-apps/developer/data-platform/impersonate-another-user)

## How impersonation works

The runtime uses:

```text
CallerObjectId: <Microsoft Entra object ID>
```

The selected `systemuser` must therefore contain `azureactivedirectoryobjectid`.

The tool deliberately does **not** fall back to `MSCRMCallerID` for a user that has no Entra object ID. System-only/non-Entra users are blocked in the UI instead of being allowed to fail after impersonation starts.

The header is applied only to Dataverse Web API requests for the current Dataverse host. The WebView2 browser remains authenticated as the person actually running the tool.

## User statuses

- **Ready** — eligible for impersonation.
- **No Entra ID** — the Dataverse user has no Microsoft Entra object ID. The row is disabled and cannot be impersonated.
- **No app access** — the user does not have access to the current model-driven app.
- **BU off** — the user's business unit is disabled.
- **User off** — the Dataverse user is disabled.
- **Access ?** — only the app-access check was inconclusive. It does not mean the user is missing an Entra ID. An Entra-backed user with this status may still be tested after a warning.

## Multiple windows

Each impersonator window uses its own WebView2 user-data folder, so different users can be tested in separate windows without intentionally sharing browser state.

## Stopping impersonation

**Stop impersonating** disables the request interception and rebuilds the isolated WebView2 context back under the real signed-in user.

## What is not impersonated

The header applies to Dataverse requests. It does not automatically impersonate identities used by other services or connectors.

For example, an embedded Canvas app that uploads a file using a SharePoint connector will still use the identity of that SharePoint/Power Platform connection. A SharePoint upload can therefore show the real signed-in user even while the surrounding Dataverse model-driven app is impersonated.

## Troubleshooting

### Bookmarklet appears to do nothing

First check:

```powershell
Get-ExecutionPolicy -List
```

If the effective policy is `AllSigned`, rerun `INSTALL-NEW-USER.ps1` and accept the CurrentUser `RemoteSigned` option, or use a runtime signed by a certificate trusted by the machine.

You can also verify the protocol registration:

```powershell
(Get-Item 'HKCU:\Software\Classes\dataverseimpersonator\shell\open\command').GetValue('')
```

and the installed files:

```powershell
Test-Path "$env:LOCALAPPDATA\DataverseImpersonator\Launch-Dataverse-Impersonator.vbs"
Test-Path "$env:LOCALAPPDATA\DataverseImpersonator\Dataverse-Impersonator.ps1"
```

### `No Entra ID`

The Dataverse `systemuser` record does not contain `azureactivedirectoryobjectid`. The row is intentionally disabled.

### `No app access`

The user is enabled but does not have access to the current model-driven app.

### `Access ?`

The tool could not conclusively verify model-driven app access. It is not the Entra-ID check.

### `BU off`

The user's business unit is disabled.

### Act on behalf privilege missing

Assign `prvActOnBehalfOfAnotherUser` directly to the caller, typically through the built-in Delegate role.

### WebView2 SDK files not found

Ensure the WebView2 .NET SDK assemblies are available in one of the locations listed under Requirements.

## Security notes

This tool can act with another user's Dataverse privileges. Restrict it to authorized administration, support, and testing scenarios. Actions made in the impersonated window can affect real Dataverse data.

Changing `CurrentUser` from `AllSigned`/`Undefined` to `RemoteSigned` is a real reduction in PowerShell script-signing enforcement for that account. The installer therefore requires explicit confirmation, changes only `CurrentUser`, records the prior value, and lets the uninstaller offer to restore it.

## Acknowledgment

The Dataverse impersonation approach is based on the same supported Dataverse impersonation headers used by tools such as **Level Up for Dynamics 365 / Power Apps**.

Original Level Up project:

https://github.com/rajyraman/Levelup-for-Dynamics-CRM
