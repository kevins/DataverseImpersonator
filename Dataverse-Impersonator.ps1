# Dataverse Impersonator
# Runtime source only. It never installs or updates the bookmarklet.
# Run this source directly and it immediately asks for the Dataverse/model-driven app URL.
# The new-user installer sets a temporary process environment variable when the bookmarklet
# launches this runtime, so bookmarklet launches do not depend on PowerShell argument parsing.
# The whole application is wrapped in one script block so it can also be copy/pasted into ISE.

& {
    $LaunchUri = [Environment]::GetEnvironmentVariable('DATAVERSE_IMPERSONATOR_LAUNCH_URI', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($LaunchUri)) {
        Remove-Item Env:\DATAVERSE_IMPERSONATOR_LAUNCH_URI -ErrorAction SilentlyContinue
    }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms

if (-not [string]::IsNullOrWhiteSpace($LaunchUri)) {
    try {
        if (-not ('DataverseImpersonatorConsoleWindow' -as [type])) {
            $consoleHideSource = @'
using System;
using System.Runtime.InteropServices;

public static class DataverseImpersonatorConsoleWindow
{
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
            Add-Type -TypeDefinition $consoleHideSource -IgnoreWarnings
        }

        $consoleHandle = [DataverseImpersonatorConsoleWindow]::GetConsoleWindow()
        if ($consoleHandle -ne [IntPtr]::Zero) {
            [DataverseImpersonatorConsoleWindow]::ShowWindow($consoleHandle, 0) | Out-Null
        }
    }
    catch {
    }
}

$protocolName = 'dataverseimpersonator'

function Get-NormalizedDataverseUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    $uri = $null
    if (-not [Uri]::TryCreate($Url.Trim(), [UriKind]::Absolute, [ref]$uri)) {
        return $null
    }

    if ($uri.Scheme -ne 'https') {
        return $null
    }

    $targetHost = $uri.Host.ToLowerInvariant()
    if ($targetHost -notmatch '(^|\.)dynamics\.com$') {
        return $null
    }

    return $uri.AbsoluteUri
}

function ConvertFrom-DataverseImpersonatorUri {
    param([Parameter(Mandatory = $true)][string]$UriText)

    $launch = $null
    if (-not [Uri]::TryCreate($UriText.Trim(), [UriKind]::Absolute, [ref]$launch)) {
        throw 'The bookmarklet launch URI was invalid.'
    }

    if ($launch.Scheme -ne $protocolName) {
        throw "Expected the $protocolName protocol."
    }

    $queryStart = $UriText.IndexOf('?')
    if ($queryStart -lt 0 -or $queryStart -ge ($UriText.Length - 1)) {
        throw 'The bookmarklet did not include a model-driven app URL.'
    }

    $query = $UriText.Substring($queryStart + 1)
    $encodedUrl = $null

    foreach ($part in ($query -split '&')) {
        if ([string]::IsNullOrWhiteSpace($part)) {
            continue
        }

        $separator = $part.IndexOf('=')
        if ($separator -lt 0) {
            continue
        }

        $name = [Uri]::UnescapeDataString($part.Substring(0, $separator))
        if ($name -eq 'url') {
            $encodedUrl = $part.Substring($separator + 1)
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($encodedUrl)) {
        throw 'The bookmarklet did not include a model-driven app URL.'
    }

    $decodedUrl = [Uri]::UnescapeDataString($encodedUrl)
    $normalized = Get-NormalizedDataverseUrl -Url $decodedUrl
    if (-not $normalized) {
        throw 'The bookmarklet URL must be an HTTPS Dataverse/model-driven app URL on dynamics.com.'
    }

    return $normalized
}

function Find-WebView2Sdk {
    $directPaths = @()

    if (-not [string]::IsNullOrWhiteSpace($env:WEBVIEW2_SDK_PATH)) {
        $directPaths += $env:WEBVIEW2_SDK_PATH
    }

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $directPaths += $PSScriptRoot
    }

    $directPaths += @(
        'C:\Program Files\Microsoft Office\root\Office16\ADDINS\Microsoft Power Query for Excel Integrated\bin',
        'C:\Program Files (x86)\Microsoft Office\root\Office16\ADDINS\Microsoft Power Query for Excel Integrated\bin'
    )

    foreach ($path in ($directPaths | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) {
            continue
        }

        $core = Join-Path $path 'Microsoft.Web.WebView2.Core.dll'
        $winForms = Join-Path $path 'Microsoft.Web.WebView2.WinForms.dll'
        $loader = Join-Path $path 'WebView2Loader.dll'

        if ((Test-Path $core) -and (Test-Path $winForms) -and (Test-Path $loader)) {
            return [PSCustomObject]@{
                ManagedPath = $path
                LoaderPath = $path
            }
        }
    }

    $searchRoots = @(
        'C:\Program Files\Microsoft Office',
        'C:\Program Files (x86)\Microsoft Office',
        (Join-Path $env:USERPROFILE '.nuget\packages\microsoft.web.webview2')
    )

    if (-not [string]::IsNullOrWhiteSpace($env:WEBVIEW2_SDK_PATH)) {
        $searchRoots = @($env:WEBVIEW2_SDK_PATH) + $searchRoots
    }

    foreach ($root in ($searchRoots | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path $root)) {
            continue
        }

        $winFormsFiles = Get-ChildItem -LiteralPath $root -Filter 'Microsoft.Web.WebView2.WinForms.dll' -Recurse -ErrorAction SilentlyContinue
        foreach ($file in $winFormsFiles) {
            $managedPath = $file.DirectoryName
            if (-not (Test-Path (Join-Path $managedPath 'Microsoft.Web.WebView2.Core.dll'))) {
                continue
            }

            $loaderCandidates = Get-ChildItem -LiteralPath $root -Filter 'WebView2Loader.dll' -Recurse -ErrorAction SilentlyContinue
            if (-not $loaderCandidates) {
                continue
            }

            $loader = $null
            if ([Environment]::Is64BitProcess) {
                $loader = $loaderCandidates | Where-Object { $_.FullName -match '(?i)(x64|win-x64)' } | Select-Object -First 1
            }
            else {
                $loader = $loaderCandidates | Where-Object { $_.FullName -match '(?i)(x86|win-x86)' } | Select-Object -First 1
            }

            if (-not $loader) {
                $loader = $loaderCandidates | Select-Object -First 1
            }

            if ($loader) {
                return [PSCustomObject]@{
                    ManagedPath = $managedPath
                    LoaderPath = $loader.DirectoryName
                }
            }
        }
    }

    return $null
}

$webViewSdk = Find-WebView2Sdk
if (-not $webViewSdk) {
    throw @'
Could not find the WebView2 .NET SDK files required by this tool:
  Microsoft.Web.WebView2.Core.dll
  Microsoft.Web.WebView2.WinForms.dll
  WebView2Loader.dll

The Microsoft Edge WebView2 Runtime alone is not enough; the .NET SDK assemblies are also required.

Supported locations include:
  - the same folder as this script
  - Microsoft Office installations that include the WebView2 SDK files
  - the user's Microsoft.Web.WebView2 NuGet package cache
  - a custom folder specified by the WEBVIEW2_SDK_PATH environment variable
'@
}

$coreDll = Join-Path $webViewSdk.ManagedPath 'Microsoft.Web.WebView2.Core.dll'
$winFormsDll = Join-Path $webViewSdk.ManagedPath 'Microsoft.Web.WebView2.WinForms.dll'
$env:PATH = "$($webViewSdk.LoaderPath);$($webViewSdk.ManagedPath);$env:PATH"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web.Extensions
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -Path $coreDll
Add-Type -Path $winFormsDll

$source = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

public sealed class DataverseUserTemplate
{
    public string SystemUserId { get; set; }
    public string AzureObjectId { get; set; }
    public string FullName { get; set; }
    public string Email { get; set; }
    public string DomainName { get; set; }
    public bool IsDisabled { get; set; }
    public string BusinessUnitName { get; set; }
    public bool BusinessUnitDisabled { get; set; }
    public bool AppAccessKnown { get; set; }
    public bool HasAppAccess { get; set; }
    public string AppAccessReason { get; set; }

    public override string ToString()
    {
        return FullName ?? Email ?? SystemUserId;
    }
}

public sealed class DataverseImpersonatorFormTemplate : Form
{
    private readonly string settingsFolder;
    private readonly JavaScriptSerializer serializer = new JavaScriptSerializer();

    private readonly WebView2 webView = new WebView2();
    private readonly TextBox urlBox = new TextBox();
    private readonly Button openButton = new Button();
    private readonly Button browserBackButton = new Button();
    private readonly Button browserForwardButton = new Button();
    private readonly Button browserRefreshButton = new Button();
    private readonly TextBox browserUrlBox = new TextBox();
    private readonly Button copyUrlButton = new Button();
    private readonly TextBox searchBox = new TextBox();
    private readonly Button searchButton = new Button();
    private readonly DataGridView userGrid = new DataGridView();
    private readonly Button impersonateButton = new Button();
    private readonly Button stopButton = new Button();
    private readonly Button verifyButton = new Button();
    private readonly Label statusLabel = new Label();
    private readonly Label currentUserLabel = new Label();
    private readonly Label environmentLabel = new Label();
    private readonly Label searchStatusLabel = new Label();
    private readonly Label injectionStatusLabel = new Label();
    private readonly Label privilegeStatusLabel = new Label();
    private readonly Timer searchTimer = new Timer();
    private readonly Timer identityTimer = new Timer();

    private CoreWebView2DevToolsProtocolEventReceiver fetchReceiver;
    private bool initialized;
    private bool impersonationEnabled;
    private bool showVerificationResult;
    private bool cdpFetchEnabled;
    private bool usingLegacyHeader;
    private bool privilegeCheckSucceeded;
    private bool hasDirectImpersonationPrivilege;
    private int cdpModifiedRequestCount;
    private int webViewModifiedRequestCount;
    private int autoVerifyAttemptCount;
    private bool autoVerificationConfirmed;
    private bool needsCleanShellOnNextImpersonation;
    private string appUrl;
    private string dataverseHost;
    private string currentFilter;
    private DataverseUserTemplate impersonatedUser;

    public DataverseImpersonatorFormTemplate(string initialAppUrl, string settingsFolder)
    {
        this.settingsFolder = settingsFolder;
        appUrl = string.IsNullOrWhiteSpace(initialAppUrl) ? string.Empty : initialAppUrl.Trim();

        Text = "Dataverse Impersonator";
        Width = 1550;
        Height = 950;
        MinimumSize = new Size(1100, 700);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 9F);

        BuildUi();
        WireUiEvents();

        Shown += async delegate { await InitializeWebViewAsync(); };
    }

    private void BuildUi()
    {
        var split = new SplitContainer();
        split.Dock = DockStyle.Fill;
        split.Size = ClientSize;
        split.Panel1MinSize = 330;
        split.Panel2MinSize = 500;
        split.SplitterDistance = 355;
        Controls.Add(split);

        var sidebar = new FlowLayoutPanel();
        sidebar.Dock = DockStyle.Fill;
        sidebar.FlowDirection = FlowDirection.TopDown;
        sidebar.WrapContents = false;
        sidebar.AutoScroll = true;
        sidebar.Padding = new Padding(14);
        sidebar.BackColor = Color.White;
        split.Panel1.Controls.Add(sidebar);

        var title = new Label();
        title.Text = "Dataverse Impersonator";
        title.Font = new Font("Segoe UI Semibold", 17F);
        title.AutoSize = false;
        title.Width = 315;
        title.Height = 42;
        sidebar.Controls.Add(title);

        var subtitle = new Label();
        subtitle.Text = "Test a model-driven app using another user's Dataverse security context.";
        subtitle.AutoSize = false;
        subtitle.Width = 315;
        subtitle.Height = 48;
        subtitle.ForeColor = Color.DimGray;
        sidebar.Controls.Add(subtitle);

        sidebar.Controls.Add(CreateSectionLabel("MODEL-DRIVEN APP"));

        urlBox.Width = 315;
        urlBox.Text = appUrl;
        sidebar.Controls.Add(urlBox);

        openButton.Text = "Open app";
        SetMainButtonSize(openButton);
        sidebar.Controls.Add(openButton);

        environmentLabel.AutoSize = false;
        environmentLabel.Width = 315;
        environmentLabel.Height = 38;
        environmentLabel.Text = "Environment: not connected";
        environmentLabel.ForeColor = Color.DimGray;
        sidebar.Controls.Add(environmentLabel);

        sidebar.Controls.Add(CreateSectionLabel("CURRENT CONTEXT"));

        var statusPanel = new Panel();
        statusPanel.Width = 315;
        statusPanel.Height = 150;
        statusPanel.BorderStyle = BorderStyle.FixedSingle;

        statusLabel.Left = 10;
        statusLabel.Top = 10;
        statusLabel.Width = 290;
        statusLabel.Height = 24;
        statusLabel.Font = new Font("Segoe UI Semibold", 10F);
        statusLabel.Text = "STARTING...";
        statusPanel.Controls.Add(statusLabel);

        currentUserLabel.Left = 10;
        currentUserLabel.Top = 38;
        currentUserLabel.Width = 290;
        currentUserLabel.Height = 102;
        currentUserLabel.Text = "Waiting for Dataverse...";
        currentUserLabel.ForeColor = Color.DimGray;
        statusPanel.Controls.Add(currentUserLabel);
        sidebar.Controls.Add(statusPanel);

        injectionStatusLabel.AutoSize = false;
        injectionStatusLabel.Width = 315;
        injectionStatusLabel.Height = 42;
        injectionStatusLabel.ForeColor = Color.DimGray;
        injectionStatusLabel.Text = "Header engine: idle";
        sidebar.Controls.Add(injectionStatusLabel);

        privilegeStatusLabel.AutoSize = false;
        privilegeStatusLabel.Width = 315;
        privilegeStatusLabel.Height = 34;
        privilegeStatusLabel.ForeColor = Color.DimGray;
        privilegeStatusLabel.Text = "Act on behalf privilege: checking...";
        sidebar.Controls.Add(privilegeStatusLabel);

        sidebar.Controls.Add(CreateSectionLabel("IMPERSONATE USER"));

        searchBox.Width = 315;
        sidebar.Controls.Add(searchBox);

        searchButton.Text = "Search";
        SetMainButtonSize(searchButton);
        sidebar.Controls.Add(searchButton);

        searchStatusLabel.AutoSize = false;
        searchStatusLabel.Width = 315;
        searchStatusLabel.Height = 60;
        searchStatusLabel.Margin = new Padding(3, 0, 3, 5);
        searchStatusLabel.ForeColor = Color.DimGray;
        searchStatusLabel.Text = "Type at least 2 characters.";
        sidebar.Controls.Add(searchStatusLabel);

        ConfigureUserGrid();
        sidebar.Controls.Add(userGrid);

        impersonateButton.Text = "Impersonate selected user";
        SetMainButtonSize(impersonateButton);
        impersonateButton.Enabled = false;
        sidebar.Controls.Add(impersonateButton);

        stopButton.Text = "Stop impersonating";
        SetMainButtonSize(stopButton);
        stopButton.Enabled = false;
        sidebar.Controls.Add(stopButton);

        verifyButton.Visible = false;

        var note = new Label();
        note.AutoSize = false;
        note.Width = 315;
        note.Height = 70;
        note.ForeColor = Color.DimGray;
        note.Text = "The app is real. Changes you make while impersonating can modify real Dataverse records. Use a development/test environment when possible.";
        sidebar.Controls.Add(note);

        var browserLayout = new TableLayoutPanel();
        browserLayout.Dock = DockStyle.Fill;
        browserLayout.ColumnCount = 1;
        browserLayout.RowCount = 2;
        browserLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 36F));
        browserLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));

        var browserBar = new Panel();
        browserBar.Dock = DockStyle.Fill;
        browserBar.Padding = new Padding(5, 4, 5, 4);
        browserBar.BackColor = SystemColors.Control;

        var browserControls = new TableLayoutPanel();
        browserControls.Dock = DockStyle.Fill;
        browserControls.RowCount = 1;
        browserControls.ColumnCount = 5;
        browserControls.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
        browserControls.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 38F));
        browserControls.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 38F));
        browserControls.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 38F));
        browserControls.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        browserControls.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 82F));

        browserBackButton.Text = "\u2190";
        browserBackButton.Dock = DockStyle.Fill;
        browserBackButton.Margin = new Padding(0, 0, 3, 0);
        browserBackButton.Font = new Font("Segoe UI Symbol", 11F);
        browserBackButton.Enabled = false;

        browserForwardButton.Text = "\u2192";
        browserForwardButton.Dock = DockStyle.Fill;
        browserForwardButton.Margin = new Padding(0, 0, 3, 0);
        browserForwardButton.Font = new Font("Segoe UI Symbol", 11F);
        browserForwardButton.Enabled = false;

        browserRefreshButton.Text = "\u21BB";
        browserRefreshButton.Dock = DockStyle.Fill;
        browserRefreshButton.Margin = new Padding(0, 0, 5, 0);
        browserRefreshButton.Font = new Font("Segoe UI Symbol", 11F);
        browserRefreshButton.Enabled = false;

        browserUrlBox.Dock = DockStyle.Fill;
        browserUrlBox.ReadOnly = true;
        browserUrlBox.BackColor = SystemColors.Window;
        browserUrlBox.Margin = new Padding(0, 0, 5, 0);

        copyUrlButton.Text = "Copy URL";
        copyUrlButton.Dock = DockStyle.Fill;
        copyUrlButton.Margin = new Padding(0);

        browserControls.Controls.Add(browserBackButton, 0, 0);
        browserControls.Controls.Add(browserForwardButton, 1, 0);
        browserControls.Controls.Add(browserRefreshButton, 2, 0);
        browserControls.Controls.Add(browserUrlBox, 3, 0);
        browserControls.Controls.Add(copyUrlButton, 4, 0);
        browserBar.Controls.Add(browserControls);

        webView.Dock = DockStyle.Fill;
        browserLayout.Controls.Add(browserBar, 0, 0);
        browserLayout.Controls.Add(webView, 0, 1);
        split.Panel2.Controls.Add(browserLayout);
    }

    private Label CreateSectionLabel(string text)
    {
        var label = new Label();
        label.Text = text;
        label.Font = new Font("Segoe UI Semibold", 8F);
        label.ForeColor = Color.DimGray;
        label.AutoSize = false;
        label.Width = 315;
        label.Height = 28;
        label.Padding = new Padding(0, 10, 0, 0);
        return label;
    }

    private void SetMainButtonSize(Button button)
    {
        button.Width = 315;
        button.Height = 34;
        button.FlatStyle = FlatStyle.System;
    }

    private void ConfigureUserGrid()
    {
        userGrid.Width = 315;
        userGrid.Height = 250;
        userGrid.AllowUserToAddRows = false;
        userGrid.AllowUserToDeleteRows = false;
        userGrid.AllowUserToResizeRows = false;
        userGrid.ReadOnly = true;
        userGrid.MultiSelect = false;
        userGrid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        userGrid.RowHeadersVisible = false;
        userGrid.AutoGenerateColumns = false;
        userGrid.BackgroundColor = Color.White;
        userGrid.BorderStyle = BorderStyle.FixedSingle;

        var nameColumn = new DataGridViewTextBoxColumn();
        nameColumn.HeaderText = "Name";
        nameColumn.Width = 105;
        userGrid.Columns.Add(nameColumn);

        var emailColumn = new DataGridViewTextBoxColumn();
        emailColumn.HeaderText = "Email";
        emailColumn.AutoSizeMode = DataGridViewAutoSizeColumnMode.Fill;
        userGrid.Columns.Add(emailColumn);

        var statusColumn = new DataGridViewTextBoxColumn();
        statusColumn.HeaderText = "Status";
        statusColumn.Width = 105;
        userGrid.Columns.Add(statusColumn);
    }

    private void WireUiEvents()
    {
        openButton.Click += delegate { OpenAppFromTextBox(); };
        copyUrlButton.Click += delegate
        {
            if (!string.IsNullOrWhiteSpace(browserUrlBox.Text))
            {
                Clipboard.SetText(browserUrlBox.Text);
            }
        };

        urlBox.KeyDown += delegate(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.SuppressKeyPress = true;
                OpenAppFromTextBox();
            }
        };

        searchTimer.Interval = 550;
        searchTimer.Tick += async delegate
        {
            searchTimer.Stop();
            await SearchUsersAsync();
        };

        searchBox.TextChanged += delegate
        {
            searchTimer.Stop();
            if (!impersonationEnabled && searchBox.Text.Trim().Length >= 2)
            {
                searchTimer.Start();
            }
        };

        searchBox.KeyDown += async delegate(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.SuppressKeyPress = true;
                searchTimer.Stop();
                await SearchUsersAsync();
            }
        };

        searchButton.Click += async delegate { await SearchUsersAsync(); };

        userGrid.SelectionChanged += delegate
        {
            impersonateButton.Enabled = !impersonationEnabled && CanImpersonateUser(GetSelectedUser());
        };

        userGrid.CellDoubleClick += async delegate
        {
            if (!impersonationEnabled && GetSelectedUser() != null)
            {
                await StartImpersonationAsync();
            }
        };

        impersonateButton.Click += async delegate { await StartImpersonationAsync(); };
        stopButton.Click += async delegate { await StopImpersonationAsync(); };

        browserBackButton.Click += delegate
        {
            if (initialized && webView.CoreWebView2 != null && webView.CoreWebView2.CanGoBack)
            {
                webView.CoreWebView2.GoBack();
            }
        };

        browserForwardButton.Click += delegate
        {
            if (initialized && webView.CoreWebView2 != null && webView.CoreWebView2.CanGoForward)
            {
                webView.CoreWebView2.GoForward();
            }
        };

        browserRefreshButton.Click += delegate
        {
            if (initialized && webView.CoreWebView2 != null)
            {
                webView.CoreWebView2.Reload();
            }
        };

        identityTimer.Interval = 1800;
        identityTimer.Tick += async delegate
        {
            identityTimer.Stop();
            if (impersonationEnabled)
            {
                await RequestAutomaticImpersonationVerificationAsync();
            }
            else
            {
                await RequestIdentityAsync();
            }
        };
    }

    private async Task InitializeWebViewAsync()
    {
        try
        {
            Directory.CreateDirectory(settingsFolder);
            SetStatus("INITIALIZING WEBVIEW2", Color.DarkGoldenrod);

            var userDataFolder = Path.Combine(
                settingsFolder,
                "Sessions",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(userDataFolder);

            var options = new CoreWebView2EnvironmentOptions(null, null, null, true);
            options.ExclusiveUserDataFolderAccess = true;
            var environment = await CoreWebView2Environment.CreateAsync(null, userDataFolder, options);
            await webView.EnsureCoreWebView2Async(environment);

            webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
            webView.CoreWebView2.WebResourceRequested += OnWebResourceRequested;
            webView.CoreWebView2.NavigationStarting += OnNavigationStarting;
            webView.CoreWebView2.NavigationCompleted += OnNavigationCompleted;
            webView.CoreWebView2.SourceChanged += OnSourceChanged;
            webView.CoreWebView2.HistoryChanged += OnHistoryChanged;

            fetchReceiver = webView.CoreWebView2.GetDevToolsProtocolEventReceiver("Fetch.requestPaused");
            fetchReceiver.DevToolsProtocolEventReceived += OnFetchRequestPaused;

            initialized = true;
            UpdateBrowserNavigationButtons();
            SetStatus("NORMAL CONTEXT", Color.DarkGreen);

            if (!string.IsNullOrWhiteSpace(appUrl))
            {
                NavigateToApp(appUrl);
            }
            else
            {
                currentUserLabel.Text = "Paste your model-driven app URL above, then click Open app.";
            }
        }
        catch (Exception ex)
        {
            SetStatus("WEBVIEW2 FAILED", Color.DarkRed);
            MessageBox.Show(
                ex.ToString(),
                "Could not start WebView2",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private void OpenAppFromTextBox()
    {
        if (!initialized)
        {
            return;
        }

        if (impersonationEnabled)
        {
            MessageBox.Show(
                "Stop impersonating before changing environments.",
                "Impersonation active",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            return;
        }

        NavigateToApp(urlBox.Text.Trim());
    }

    private void NavigateToApp(string url)
    {
        Uri uri;
        if (!Uri.TryCreate(url, UriKind.Absolute, out uri) || uri.Scheme != Uri.UriSchemeHttps)
        {
            MessageBox.Show(
                "Paste the full HTTPS URL of your model-driven app.",
                "Invalid app URL",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        appUrl = uri.AbsoluteUri;
        urlBox.Text = appUrl;
        if (LooksLikeDataverseHost(uri.Host))
        {
            ConfigureDataverseHost(uri.Host);
        }

        webView.CoreWebView2.Navigate(appUrl);
    }

    private bool LooksLikeDataverseHost(string host)
    {
        if (string.IsNullOrWhiteSpace(host))
        {
            return false;
        }

        return host.IndexOf(".dynamics.com", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private void ConfigureDataverseHost(string host)
    {
        if (!initialized || webView.CoreWebView2 == null || string.IsNullOrWhiteSpace(host))
        {
            return;
        }

        if (string.Equals(dataverseHost, host, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (!string.IsNullOrWhiteSpace(currentFilter))
        {
            try
            {
                webView.CoreWebView2.RemoveWebResourceRequestedFilter(
                    currentFilter,
                    CoreWebView2WebResourceContext.All,
                    CoreWebView2WebResourceRequestSourceKinds.All);
            }
            catch
            {
            }
        }

        dataverseHost = host;
        currentFilter = "https://" + dataverseHost + "/api/data/v*";

        webView.CoreWebView2.AddWebResourceRequestedFilter(
            currentFilter,
            CoreWebView2WebResourceContext.All,
            CoreWebView2WebResourceRequestSourceKinds.All);

        environmentLabel.Text = "Environment: " + dataverseHost;
    }

    private void OnNavigationStarting(object sender, CoreWebView2NavigationStartingEventArgs e)
    {
        browserUrlBox.Text = e.Uri ?? string.Empty;

        Uri uri;
        if (!Uri.TryCreate(e.Uri, UriKind.Absolute, out uri))
        {
            return;
        }

        if (LooksLikeDataverseHost(uri.Host))
        {
            ConfigureDataverseHost(uri.Host);

            if (uri.AbsolutePath.IndexOf("main.aspx", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                appUrl = uri.AbsoluteUri;
                urlBox.Text = appUrl;
            }
        }
    }

    private void OnSourceChanged(object sender, CoreWebView2SourceChangedEventArgs e)
    {
        try
        {
            if (webView.Source != null &&
                webView.Source.IsAbsoluteUri &&
                webView.Source.Scheme == Uri.UriSchemeHttps)
            {
                browserUrlBox.Text = webView.Source.AbsoluteUri;
            }
        }
        catch
        {
        }

        UpdateBrowserNavigationButtons();
    }

    private void OnHistoryChanged(object sender, object e)
    {
        UpdateBrowserNavigationButtons();
    }

    private void UpdateBrowserNavigationButtons()
    {
        if (IsDisposed)
        {
            return;
        }

        if (InvokeRequired)
        {
            BeginInvoke((Action)UpdateBrowserNavigationButtons);
            return;
        }

        var core = initialized ? webView.CoreWebView2 : null;
        browserBackButton.Enabled = core != null && core.CanGoBack;
        browserForwardButton.Enabled = core != null && core.CanGoForward;
        browserRefreshButton.Enabled = core != null;
    }

    private async void OnNavigationCompleted(object sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        UpdateBrowserNavigationButtons();

        if (!e.IsSuccess)
        {
            currentUserLabel.Text = "Navigation failed: " + e.WebErrorStatus;
            return;
        }

        if (IsCurrentlyOnDataverse())
        {
            searchButton.Enabled = !impersonationEnabled;
            searchBox.Enabled = !impersonationEnabled;

            if (!impersonationEnabled)
            {
                await CheckDirectImpersonationPrivilegeAsync();
                identityTimer.Stop();
                identityTimer.Interval = 1800;
                identityTimer.Start();
            }
            else if (!autoVerificationConfirmed)
            {
                SetStatus("VERIFYING: " + impersonatedUser.FullName, Color.DarkGoldenrod);
                currentUserLabel.Text = "Checking the model-driven app shell for the impersonated user...";
                identityTimer.Stop();
                identityTimer.Interval = 1200;
                identityTimer.Start();
            }
        }
        else
        {
            currentUserLabel.Text = "Complete sign-in in the browser window.";
        }
    }

    private bool IsCurrentlyOnDataverse()
    {
        try
        {
            if (webView.Source == null || string.IsNullOrWhiteSpace(dataverseHost))
            {
                return false;
            }

            return string.Equals(webView.Source.Host, dataverseHost, StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private async Task CheckDirectImpersonationPrivilegeAsync()
    {
        if (!initialized || !IsCurrentlyOnDataverse() || impersonationEnabled)
        {
            return;
        }

        privilegeCheckSucceeded = false;
        hasDirectImpersonationPrivilege = false;
        privilegeStatusLabel.Text = "Act on behalf privilege: checking...";
        privilegeStatusLabel.ForeColor = Color.DimGray;

        var script = @"
(function () {
    var headers = {
        'Accept': 'application/json',
        'OData-MaxVersion': '4.0',
        'OData-Version': '4.0',
        'If-None-Match': 'null'
    };

    fetch('/api/data/v9.2/WhoAmI', {
        credentials: 'include',
        cache: 'no-store',
        headers: headers
    })
        .then(function (response) {
            if (!response.ok) {
                return response.text().then(function (text) {
                    throw new Error('WhoAmI HTTP ' + response.status + ': ' + text);
                });
            }
            return response.json();
        })
        .then(function (who) {
            var userId = who.UserId || '';
            if (!userId) {
                throw new Error('WhoAmI did not return a UserId.');
            }

            var url = '/api/data/v9.2/systemusers(' + userId + ')' +
                '/Microsoft.Dynamics.CRM.RetrieveUserPrivilegeByPrivilegeName' +
                ""(PrivilegeName='prvActOnBehalfOfAnotherUser')"";

            return fetch(url, {
                credentials: 'include',
                cache: 'no-store',
                headers: headers
            });
        })
        .then(function (response) {
            if (!response.ok) {
                return response.text().then(function (text) {
                    throw new Error('Privilege check HTTP ' + response.status + ': ' + text);
                });
            }
            return response.json();
        })
        .then(function (data) {
            var privileges = data.RolePrivileges || [];
            window.chrome.webview.postMessage(JSON.stringify({
                type: 'privilege',
                ok: true,
                hasPrivilege: privileges.length > 0
            }));
        })
        .catch(function (error) {
            window.chrome.webview.postMessage(JSON.stringify({
                type: 'privilege',
                ok: false,
                error: error.message || String(error)
            }));
        });
})();";

        try
        {
            await webView.ExecuteScriptAsync(script);
        }
        catch (Exception)
        {
            privilegeCheckSucceeded = false;
            privilegeStatusLabel.Text = "Act on behalf privilege: could not check";
            privilegeStatusLabel.ForeColor = Color.DarkGoldenrod;
        }
    }

    private async Task BeginNetworkImpersonationAsync(DataverseUserTemplate user, bool useLegacy)
    {
        if (user == null)
        {
            SetStatus("IMPERSONATION NOT STARTED", Color.DarkRed);
            currentUserLabel.Text = "The selected user is no longer available.";
            return;
        }
        impersonatedUser = user;
        impersonationEnabled = true;
        usingLegacyHeader = useLegacy;
        cdpModifiedRequestCount = 0;
        webViewModifiedRequestCount = 0;
        autoVerifyAttemptCount = 0;
        autoVerificationConfirmed = false;

        searchTimer.Stop();
        searchBox.Enabled = false;
        searchButton.Enabled = false;
        impersonateButton.Enabled = false;
        stopButton.Enabled = true;

        SetStatus("STARTING: " + user.FullName, Color.DarkRed);
        currentUserLabel.Text =
            "Applying network-level impersonation and reloading the app...";
        UpdateInjectionStatus();

        // Starting impersonation deliberately keeps the already-authenticated browser profile.
        // Earlier versions that cleared all WebView2 browsing data before switching users could
        // make Power Apps' AppContextLoader fail for otherwise impersonatable users.  This follows
        // the same transition that previously worked: enable request interception, then navigate
        // the existing authenticated tab to the exact current model-driven-app URL.
        var targetUrl = GetCurrentDataversePageUrl();
        await EnableCdpInterceptionAsync();

        // After returning to the real user, Power Apps can keep the caller's shell/profile
        // presentation in DOM storage even though subsequent Dataverse requests are correctly
        // impersonated.  Before the next impersonation, clear only client-side app/cache state
        // while preserving cookies and SSO, then rebuild the shell under the impersonated header.
        if (needsCleanShellOnNextImpersonation)
        {
            await PrepareShellForNewImpersonationAsync();
        }

        if (!string.IsNullOrWhiteSpace(targetUrl))
        {
            webView.CoreWebView2.Navigate(targetUrl);
        }
        else if (!string.IsNullOrWhiteSpace(appUrl))
        {
            webView.CoreWebView2.Navigate(appUrl);
        }
        else
        {
            webView.CoreWebView2.Reload();
        }
    }

    private string GetImpersonationHeaderName()
    {
        return usingLegacyHeader ? "MSCRMCallerID" : "CallerObjectId";
    }

    private string GetImpersonationHeaderValue()
    {
        if (impersonatedUser == null)
        {
            return string.Empty;
        }

        return usingLegacyHeader ? impersonatedUser.SystemUserId : impersonatedUser.AzureObjectId;
    }

    private void UpdateInjectionStatus()
    {
        if (IsDisposed)
        {
            return;
        }

        if (InvokeRequired)
        {
            BeginInvoke((Action)UpdateInjectionStatus);
            return;
        }

        if (!impersonationEnabled)
        {
            injectionStatusLabel.Text = "Header engine: idle";
            return;
        }

        var mode = usingLegacyHeader ? "MSCRMCallerID" : "CallerObjectId";
        var cdpState = cdpFetchEnabled ? "CDP active" : "CDP fallback";
        injectionStatusLabel.Text =
            "Header: " + mode + " | " + cdpState +
            "\r\nModified requests: CDP " + cdpModifiedRequestCount +
            ", WebView2 " + webViewModifiedRequestCount;
    }

    private void OnWebResourceRequested(object sender, CoreWebView2WebResourceRequestedEventArgs e)
    {
        if (!impersonationEnabled || impersonatedUser == null)
        {
            return;
        }

        var headerValue = GetImpersonationHeaderValue();
        if (string.IsNullOrWhiteSpace(headerValue))
        {
            return;
        }

        Uri requestUri;
        if (!Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out requestUri))
        {
            return;
        }

        if (!string.Equals(requestUri.Host, dataverseHost, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (!requestUri.AbsolutePath.StartsWith("/api/data/v", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        try
        {
            e.Request.Headers.SetHeader(GetImpersonationHeaderName(), headerValue);
            webViewModifiedRequestCount++;
            UpdateInjectionStatus();
        }
        catch
        {
        }
    }


    private async void OnFetchRequestPaused(
        object sender,
        CoreWebView2DevToolsProtocolEventReceivedEventArgs e)
    {
        string requestId = string.Empty;

        try
        {
            var data = serializer.DeserializeObject(e.ParameterObjectAsJson) as Dictionary<string, object>;
            if (data == null || !data.ContainsKey("requestId"))
            {
                return;
            }

            requestId = Convert.ToString(data["requestId"]);
            if (string.IsNullOrWhiteSpace(requestId))
            {
                return;
            }

            if (!impersonationEnabled || impersonatedUser == null)
            {
                await ContinueCdpRequestAsync(requestId, null);
                return;
            }

            var request = data.ContainsKey("request")
                ? data["request"] as Dictionary<string, object>
                : null;

            if (request == null)
            {
                await ContinueCdpRequestAsync(requestId, null);
                return;
            }

            var url = request.ContainsKey("url") ? Convert.ToString(request["url"]) : string.Empty;
            Uri requestUri;
            if (!Uri.TryCreate(url, UriKind.Absolute, out requestUri) ||
                !string.Equals(requestUri.Host, dataverseHost, StringComparison.OrdinalIgnoreCase) ||
                !requestUri.AbsolutePath.StartsWith("/api/data/v", StringComparison.OrdinalIgnoreCase))
            {
                await ContinueCdpRequestAsync(requestId, null);
                return;
            }

            var headerValue = GetImpersonationHeaderValue();
            if (string.IsNullOrWhiteSpace(headerValue))
            {
                await ContinueCdpRequestAsync(requestId, null);
                return;
            }

            var headerEntries = new List<Dictionary<string, string>>();
            var headers = request.ContainsKey("headers")
                ? request["headers"] as Dictionary<string, object>
                : null;

            if (headers != null)
            {
                foreach (var pair in headers)
                {
                    if (pair.Key.StartsWith(":", StringComparison.Ordinal))
                    {
                        continue;
                    }

                    if (string.Equals(pair.Key, "CallerObjectId", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(pair.Key, "MSCRMCallerID", StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    headerEntries.Add(new Dictionary<string, string>
                    {
                        { "name", pair.Key },
                        { "value", pair.Value == null ? string.Empty : Convert.ToString(pair.Value) }
                    });
                }
            }

            headerEntries.Add(new Dictionary<string, string>
            {
                { "name", GetImpersonationHeaderName() },
                { "value", headerValue }
            });

            await ContinueCdpRequestAsync(requestId, headerEntries);
            cdpModifiedRequestCount++;
            UpdateInjectionStatus();
        }
        catch
        {
            if (!string.IsNullOrWhiteSpace(requestId))
            {
                ResumeCdpRequestWithoutChanges(requestId);
            }
        }
    }

    private async void ResumeCdpRequestWithoutChanges(string requestId)
    {
        try
        {
            await ContinueCdpRequestAsync(requestId, null);
        }
        catch
        {
        }
    }

    private async Task ContinueCdpRequestAsync(
        string requestId,
        List<Dictionary<string, string>> headers)
    {
        var parameters = new Dictionary<string, object>();
        parameters["requestId"] = requestId;

        if (headers != null)
        {
            parameters["headers"] = headers;
        }

        await webView.CoreWebView2.CallDevToolsProtocolMethodAsync(
            "Fetch.continueRequest",
            serializer.Serialize(parameters));
    }

    private async Task EnableCdpInterceptionAsync()
    {
        cdpModifiedRequestCount = 0;
        webViewModifiedRequestCount = 0;

        if (string.IsNullOrWhiteSpace(dataverseHost))
        {
            cdpFetchEnabled = false;
            UpdateInjectionStatus();
            return;
        }

        try
        {
            if (cdpFetchEnabled)
            {
                await webView.CoreWebView2.CallDevToolsProtocolMethodAsync("Fetch.disable", "{}");
                cdpFetchEnabled = false;
            }

            var pattern = "https://" + dataverseHost + "/api/data/v*";
            var patternJson = serializer.Serialize(pattern);
            var parameters =
                "{\"patterns\":[{\"urlPattern\":" + patternJson +
                ",\"requestStage\":\"Request\"}]}";

            await webView.CoreWebView2.CallDevToolsProtocolMethodAsync(
                "Fetch.enable",
                parameters);

            cdpFetchEnabled = true;
        }
        catch
        {
            cdpFetchEnabled = false;
        }

        UpdateInjectionStatus();
    }

    private async Task DisableCdpInterceptionAsync()
    {
        if (!cdpFetchEnabled)
        {
            return;
        }

        try
        {
            await webView.CoreWebView2.CallDevToolsProtocolMethodAsync("Fetch.disable", "{}");
        }
        catch
        {
        }

        cdpFetchEnabled = false;
        UpdateInjectionStatus();
    }

    private async Task SearchUsersAsync()
    {
        if (!initialized || impersonationEnabled)
        {
            return;
        }

        var query = searchBox.Text.Trim();
        if (query.Length < 2)
        {
            searchStatusLabel.Text = "Type at least 2 characters.";
            userGrid.Rows.Clear();
            return;
        }

        if (!IsCurrentlyOnDataverse())
        {
            searchStatusLabel.Text = "Open the model-driven app first.";
            return;
        }

        searchStatusLabel.Text = "Searching users and checking app access...";
        searchButton.Enabled = false;
        userGrid.Rows.Clear();
        impersonateButton.Enabled = false;

        var queryJson = serializer.Serialize(query);
        var script = @"
(function () {
    var q = " + queryJson + @";
    var escaped = q.replace(/'/g, ""''"");
    var filter = ""(contains(fullname,'"" + escaped + ""') or contains(internalemailaddress,'"" + escaped + ""') or contains(domainname,'"" + escaped + ""'))"";
    var userUrl = ""/api/data/v9.2/systemusers?$select=systemuserid,fullname,internalemailaddress,domainname,azureactivedirectoryobjectid,isdisabled,_businessunitid_value&$expand=businessunitid($select=businessunitid,name,isdisabled)&$filter="" + encodeURIComponent(filter) + ""&$orderby=fullname asc&$top=20"";

    var appId = '';
    try {
        appId = (new URL(window.location.href)).searchParams.get('appid') || '';
    } catch (ignoreUrl) {
    }
    appId = appId.replace(/[{}]/g, '').trim();

    function fetchJson(url) {
        return fetch(url, {
            credentials: 'include',
            cache: 'no-store',
            headers: {
                'Accept': 'application/json',
                'OData-MaxVersion': '4.0',
                'OData-Version': '4.0',
                'If-None-Match': 'null'
            }
        }).then(function (response) {
            if (!response.ok) {
                return response.text().then(function (text) {
                    throw new Error('HTTP ' + response.status + ': ' + text);
                });
            }
            return response.json();
        });
    }

    function addRoleKeys(target, role) {
        var roleId = ((role && role.roleid) || '').toLowerCase();
        var rootId = ((role && role._parentrootroleid_value) || '').toLowerCase();
        if (roleId) target[roleId] = true;
        if (rootId) target[rootId] = true;
    }

    function userHasMatchingAppRole(userRoles, appRoleKeys) {
        for (var i = 0; i < userRoles.length; i++) {
            var keys = {};
            addRoleKeys(keys, userRoles[i]);
            for (var key in keys) {
                if (Object.prototype.hasOwnProperty.call(keys, key) && appRoleKeys[key]) {
                    return true;
                }
            }
        }
        return false;
    }

    var appRolesPromise;
    if (appId) {
        appRolesPromise = fetchJson(
            '/api/data/v9.2/appmodules(' + appId + ')/appmoduleroles_association' +
            '?$select=roleid,name,_parentrootroleid_value'
        ).then(function (data) {
            return { ok: true, roles: data.value || [] };
        }).catch(function (error) {
            return { ok: false, roles: [], error: error.message || String(error) };
        });
    } else {
        appRolesPromise = Promise.resolve({ ok: false, roles: [], error: 'No appid was found in the current model-driven app URL.' });
    }

    Promise.all([fetchJson(userUrl), appRolesPromise])
        .then(function (results) {
            var rawUsers = results[0].value || [];
            var appRoleResult = results[1];
            var appRoleKeys = {};

            (appRoleResult.roles || []).forEach(function (role) {
                addRoleKeys(appRoleKeys, role);
            });

            var canCheckRoleAccess = appRoleResult.ok && (appRoleResult.roles || []).length > 0;

            var checks = rawUsers.map(function (u) {
                var user = {
                    systemuserid: u.systemuserid || '',
                    azureobjectid: u.azureactivedirectoryobjectid || '',
                    fullname: u.fullname || '',
                    email: u.internalemailaddress || '',
                    domainname: u.domainname || '',
                    userdisabled: u.isdisabled === true,
                    businessunitname: u.businessunitid && u.businessunitid.name ? u.businessunitid.name : '',
                    businessunitdisabled: u.businessunitid && u.businessunitid.isdisabled === true,
                    appaccessknown: false,
                    hasappaccess: true,
                    appaccessreason: ''
                };

                if (!canCheckRoleAccess) {
                    user.appaccessreason = appRoleResult.ok
                        ? 'This app does not expose an app-specific role list, so access could not be pre-checked.'
                        : 'App access check unavailable: ' + (appRoleResult.error || 'unknown error');
                    return Promise.resolve(user);
                }

                if (!user.azureobjectid) {
                    user.appaccessreason = 'No Microsoft Entra object ID is available, so effective app roles could not be checked.';
                    return Promise.resolve(user);
                }

                var rolesUrl = '/api/data/v9.2/RetrieveAadUserRoles(DirectoryObjectId=' + user.azureobjectid + ')' +
                    '?$select=roleid,name,_parentrootroleid_value';

                return fetchJson(rolesUrl)
                    .then(function (roleData) {
                        var roles = roleData.value || [];
                        if (userHasMatchingAppRole(roles, appRoleKeys)) {
                            user.appaccessknown = true;
                            user.hasappaccess = true;
                            user.appaccessreason = 'User has a security role associated with this model-driven app.';
                            return user;
                        }

                        var writePrivilegeUrl = '/api/data/v9.2/systemusers(' + user.systemuserid + ')' +
                            '/Microsoft.Dynamics.CRM.RetrieveUserPrivilegeByPrivilegeName' +
                            ""(PrivilegeName='prvWriteAppModule')"";
                        var createPrivilegeUrl = '/api/data/v9.2/systemusers(' + user.systemuserid + ')' +
                            '/Microsoft.Dynamics.CRM.RetrieveUserPrivilegeByPrivilegeName' +
                            ""(PrivilegeName='prvCreateAppModule')"";

                        return Promise.all([
                            fetchJson(writePrivilegeUrl).catch(function () { return null; }),
                            fetchJson(createPrivilegeUrl).catch(function () { return null; })
                        ]).then(function (privilegeResults) {
                            var writePrivileges = privilegeResults[0] && privilegeResults[0].RolePrivileges
                                ? privilegeResults[0].RolePrivileges : [];
                            var createPrivileges = privilegeResults[1] && privilegeResults[1].RolePrivileges
                                ? privilegeResults[1].RolePrivileges : [];

                            if (writePrivileges.length > 0 || createPrivileges.length > 0) {
                                user.appaccessknown = true;
                                user.hasappaccess = true;
                                user.appaccessreason = 'User has Model-driven App create/write privilege and can access apps without an associated app role.';
                            } else if (privilegeResults[0] !== null || privilegeResults[1] !== null) {
                                user.appaccessknown = true;
                                user.hasappaccess = false;
                                user.appaccessreason = 'User is not associated with any security role assigned to this model-driven app.';
                            } else {
                                user.appaccessknown = false;
                                user.hasappaccess = true;
                                user.appaccessreason = 'No matching app role was found, but the maker-privilege check could not be completed.';
                            }

                            return user;
                        });
                    })
                    .catch(function (error) {
                        user.appaccessknown = false;
                        user.hasappaccess = true;
                        user.appaccessreason = 'Could not retrieve effective user roles: ' + (error.message || String(error));
                        return user;
                    });
            });

            return Promise.all(checks);
        })
        .then(function (users) {
            window.chrome.webview.postMessage(JSON.stringify({ type: 'search', ok: true, users: users }));
        })
        .catch(function (error) {
            window.chrome.webview.postMessage(JSON.stringify({ type: 'search', ok: false, error: error.message || String(error) }));
        });
})();";

        try
        {
            await webView.ExecuteScriptAsync(script);
        }
        catch (Exception ex)
        {
            searchButton.Enabled = true;
            searchStatusLabel.Text = "Search failed: " + ex.Message;
        }
    }

    private async Task RequestAutomaticImpersonationVerificationAsync()
    {
        if (!initialized || !impersonationEnabled || impersonatedUser == null || !IsCurrentlyOnDataverse())
        {
            return;
        }

        autoVerifyAttemptCount++;

        var expectedNameJson = serializer.Serialize(impersonatedUser.FullName ?? string.Empty);
        var expectedEmailJson = serializer.Serialize(impersonatedUser.Email ?? string.Empty);
        var expectedSystemUserIdJson = serializer.Serialize(impersonatedUser.SystemUserId ?? string.Empty);
        var expectedAzureObjectIdJson = serializer.Serialize(impersonatedUser.AzureObjectId ?? string.Empty);

        var script = @"
(function () {
    var expectedName = " + expectedNameJson + @";
    var expectedEmail = " + expectedEmailJson + @";
    var expectedSystemUserId = " + expectedSystemUserIdJson + @";
    var expectedAzureObjectId = " + expectedAzureObjectIdJson + @";

    function clean(value) {
        return (value || '').toString().toLowerCase().replace(/[^a-z0-9@._-]+/g, ' ').replace(/\s+/g, ' ').trim();
    }

    function namesMatch(combined, expected) {
        var name = clean(expected);
        if (!name) return false;
        var parts = name.split(' ').filter(function (x) { return x.length >= 2; });
        if (parts.length === 0) return false;
        var matched = 0;
        for (var i = 0; i < parts.length; i++) {
            if (combined.indexOf(parts[i]) >= 0) matched++;
        }
        return matched >= Math.min(2, parts.length);
    }

    try {
        var evidence = [];
        var xrmUserId = '';
        var xrmUserName = '';

        try {
            var context = null;
            if (window.Xrm && Xrm.Utility && Xrm.Utility.getGlobalContext) {
                context = Xrm.Utility.getGlobalContext();
            } else if (typeof window.GetGlobalContext === 'function') {
                context = window.GetGlobalContext();
            }

            if (context && context.userSettings) {
                xrmUserId = (context.userSettings.userId || '').replace(/[{}]/g, '');
                xrmUserName = context.userSettings.userName || '';
                evidence.push(xrmUserId);
                evidence.push(xrmUserName);
            }
        } catch (ignoreXrm) {
        }

        var selectors = [
            '#O365_MainLink_Me',
            '#mectrl_main_trigger',
            '#mectrl_headerPicture',
            '#mectrl_currentAccount_primary',
            '#mectrl_currentAccount_secondary',
            '#mectrl_currentAccount_picture'
        ];

        selectors.forEach(function (selector) {
            var el = document.querySelector(selector);
            if (!el) return;

            ['aria-label', 'title', 'alt', 'data-id'].forEach(function (attr) {
                var value = el.getAttribute && el.getAttribute(attr);
                if (value) evidence.push(value);
            });

            if (el.textContent) evidence.push(el.textContent);
            if (el.src) evidence.push(el.src);

            var img = el.querySelector && el.querySelector('img');
            if (img) {
                if (img.alt) evidence.push(img.alt);
                if (img.src) evidence.push(img.src);
            }
        });

        var candidates = document.querySelectorAll('button,a,[role=button],img');
        for (var i = 0; i < candidates.length; i++) {
            var el = candidates[i];
            var rect = el.getBoundingClientRect();
            if (rect.top < 140 && rect.bottom > 0 && rect.right > (window.innerWidth * 0.68)) {
                ['aria-label', 'title', 'alt'].forEach(function (attr) {
                    var value = el.getAttribute && el.getAttribute(attr);
                    if (value) evidence.push(value);
                });
                if (el.textContent) evidence.push(el.textContent);
                if (el.src) evidence.push(el.src);
            }
        }

        var combined = clean(evidence.join(' | '));
        var expectedSystemId = clean(expectedSystemUserId);
        var expectedAzureId = clean(expectedAzureObjectId);
        var expectedMail = clean(expectedEmail);
        var actualXrmId = clean(xrmUserId);

        var matched =
            (!!expectedSystemId && actualXrmId === expectedSystemId) ||
            namesMatch(clean(xrmUserName), expectedName) ||
            (!!expectedMail && combined.indexOf(expectedMail) >= 0) ||
            (!!expectedSystemId && combined.indexOf(expectedSystemId) >= 0) ||
            (!!expectedAzureId && combined.indexOf(expectedAzureId) >= 0) ||
            namesMatch(combined, expectedName);

        var bodyText = document.body ? document.body.innerText || '' : '';
        var has502 = bodyText.indexOf('502') >= 0;
        var appError = has502 && (
            bodyText.indexOf('RetrieveUserContext:') >= 0 ||
            bodyText.indexOf('AppContextLoader:') >= 0 ||
            bodyText.indexOf('UciError:') >= 0 ||
            bodyText.indexOf('Web server received an invalid response while acting as a gateway or proxy server') >= 0
        );

        window.chrome.webview.postMessage(JSON.stringify({
            type: 'shellidentity',
            ok: true,
            matched: !!matched,
            xrmUserId: xrmUserId,
            xrmUserName: xrmUserName,
            evidence: evidence.join(' | ').substring(0, 1800),
            appError: appError
        }));
    } catch (error) {
        window.chrome.webview.postMessage(JSON.stringify({
            type: 'shellidentity',
            ok: false,
            error: error.message || String(error)
        }));
    }
})();";

        try
        {
            await webView.ExecuteScriptAsync(script);
        }
        catch (Exception ex)
        {
            HandleAutomaticVerificationFailure(ex.Message);
        }
    }

    private async Task RequestIdentityAsync()
    {
        if (!initialized || !IsCurrentlyOnDataverse())
        {
            return;
        }

        var script = @"
(function () {
    try {
        var context = null;

        if (window.Xrm && Xrm.Utility && Xrm.Utility.getGlobalContext) {
            context = Xrm.Utility.getGlobalContext();
        } else if (typeof window.GetGlobalContext === 'function') {
            context = window.GetGlobalContext();
        }

        if (!context || !context.userSettings) {
            window.chrome.webview.postMessage(JSON.stringify({
                type: 'identity',
                ok: false,
                source: 'Xrm',
                error: 'The model-driven app user context is not available yet.'
            }));
            return;
        }

        var settings = context.userSettings;
        window.chrome.webview.postMessage(JSON.stringify({
            type: 'identity',
            ok: true,
            source: 'Xrm',
            userid: (settings.userId || '').replace(/[{}]/g, ''),
            fullname: settings.userName || '',
            email: '',
            domainname: ''
        }));
    } catch (error) {
        window.chrome.webview.postMessage(JSON.stringify({
            type: 'identity',
            ok: false,
            source: 'Xrm',
            error: error.message || String(error)
        }));
    }
})();";

        try
        {
            await webView.ExecuteScriptAsync(script);
        }
        catch (Exception ex)
        {
            HandleIdentityError(ex.Message);
        }
    }

    private void OnWebMessageReceived(object sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        string message;
        try
        {
            message = e.TryGetWebMessageAsString();
        }
        catch
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(message))
        {
            return;
        }

        Dictionary<string, object> data;
        try
        {
            data = serializer.DeserializeObject(message) as Dictionary<string, object>;
        }
        catch
        {
            return;
        }

        if (data == null || !data.ContainsKey("type"))
        {
            return;
        }

        var type = Convert.ToString(data["type"]);
        if (string.Equals(type, "search", StringComparison.OrdinalIgnoreCase))
        {
            HandleSearchMessage(data);
        }
        else if (string.Equals(type, "identity", StringComparison.OrdinalIgnoreCase))
        {
            HandleIdentityMessage(data);
        }
        else if (string.Equals(type, "privilege", StringComparison.OrdinalIgnoreCase))
        {
            HandlePrivilegeMessage(data);
        }
        else if (string.Equals(type, "shellidentity", StringComparison.OrdinalIgnoreCase))
        {
            HandleShellIdentityMessage(data);
        }
    }

    private bool MessageSucceeded(Dictionary<string, object> data)
    {
        return data.ContainsKey("ok") && Convert.ToBoolean(data["ok"]);
    }

    private string GetMessageString(Dictionary<string, object> data, string key)
    {
        if (!data.ContainsKey(key) || data[key] == null)
        {
            return string.Empty;
        }

        return Convert.ToString(data[key]);
    }

    private bool GetMessageBool(Dictionary<string, object> data, string key)
    {
        if (!data.ContainsKey(key) || data[key] == null)
        {
            return false;
        }

        try
        {
            return Convert.ToBoolean(data[key]);
        }
        catch
        {
            return false;
        }
    }

    private async void HandleShellIdentityMessage(Dictionary<string, object> data)
    {
        if (!impersonationEnabled || impersonatedUser == null)
        {
            return;
        }

        if (!MessageSucceeded(data))
        {
            HandleAutomaticVerificationFailure(GetMessageString(data, "error"));
            return;
        }

        if (GetMessageBool(data, "appError"))
        {
            SetStatus("IMPERSONATION APP ERROR: " + impersonatedUser.FullName, Color.DarkRed);
            currentUserLabel.Text =
                BuildUserDisplay(
                    impersonatedUser.FullName,
                    impersonatedUser.Email,
                    impersonatedUser.DomainName) +
                "\r\nThe impersonation header was applied, but the model-driven app could not load this user's app context." +
                "\r\nNo automatic retries are performed. Stop impersonating, confirm the user has access to this app, and search again.";
            UpdateInjectionStatus();
            return;
        }

        if (GetMessageBool(data, "matched"))
        {
            autoVerificationConfirmed = true;
                currentUserLabel.Text =
                BuildUserDisplay(
                    impersonatedUser.FullName,
                    impersonatedUser.Email,
                    impersonatedUser.DomainName) +
                "\r\nVerified by the model-driven app.";
            SetStatus("IMPERSONATING: " + impersonatedUser.FullName, Color.DarkGreen);
            UpdateInjectionStatus();
            return;
        }

        if (autoVerifyAttemptCount < 12)
        {
            SetStatus("IMPERSONATING: " + impersonatedUser.FullName, Color.DarkGreen);
            currentUserLabel.Text =
                BuildUserDisplay(
                    impersonatedUser.FullName,
                    impersonatedUser.Email,
                    impersonatedUser.DomainName) +
                "\r\nImpersonation header active; verifying app identity...";
            identityTimer.Stop();
            identityTimer.Interval = 1200;
            identityTimer.Start();
            return;
        }

        autoVerificationConfirmed = false;
        SetStatus("IMPERSONATING: " + impersonatedUser.FullName, Color.DarkGreen);
        currentUserLabel.Text =
            BuildUserDisplay(
                impersonatedUser.FullName,
                impersonatedUser.Email,
                impersonatedUser.DomainName) +
            "\r\nImpersonation header is active. The UI identity check did not expose enough information to confirm automatically.";
        UpdateInjectionStatus();
    }

    private void HandleAutomaticVerificationFailure(string error)
    {
        if (!impersonationEnabled || impersonatedUser == null)
        {
            return;
        }

        if (autoVerifyAttemptCount < 10)
        {
            identityTimer.Stop();
            identityTimer.Interval = 1200;
            identityTimer.Start();
            return;
        }

        autoVerificationConfirmed = false;
        SetStatus("IMPERSONATING: " + impersonatedUser.FullName, Color.DarkGreen);
        currentUserLabel.Text = BuildUserDisplay(
            impersonatedUser.FullName,
            impersonatedUser.Email,
            impersonatedUser.DomainName) +
            "\r\nImpersonation header is active. The UI identity check was unavailable.";
        UpdateInjectionStatus();
    }

    private void HandlePrivilegeMessage(Dictionary<string, object> data)
    {

        if (!MessageSucceeded(data))
        {
            privilegeCheckSucceeded = false;
            hasDirectImpersonationPrivilege = false;
            privilegeStatusLabel.Text = "Act on behalf privilege: could not check";
            privilegeStatusLabel.ForeColor = Color.DarkGoldenrod;
            return;
        }

        privilegeCheckSucceeded = true;
        hasDirectImpersonationPrivilege = GetMessageBool(data, "hasPrivilege");

        if (hasDirectImpersonationPrivilege)
        {
            privilegeStatusLabel.Text = "Act on behalf privilege: PRESENT";
            privilegeStatusLabel.ForeColor = Color.DarkGreen;
        }
        else
        {
            privilegeStatusLabel.Text = "Act on behalf privilege: MISSING";
            privilegeStatusLabel.ForeColor = Color.DarkRed;
        }
    }

    private void HandleSearchMessage(Dictionary<string, object> data)
    {
        searchButton.Enabled = !impersonationEnabled;
        userGrid.Rows.Clear();

        if (!MessageSucceeded(data))
        {
            var error = GetMessageString(data, "error");
            searchStatusLabel.Text = "Search failed.";
            MessageBox.Show(
                FriendlyDataverseError(error),
                "Could not search users",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return;
        }

        var count = 0;
        if (data.ContainsKey("users") && data["users"] is IEnumerable)
        {
            foreach (var item in (IEnumerable)data["users"])
            {
                var userData = item as Dictionary<string, object>;
                if (userData == null)
                {
                    continue;
                }

                var user = new DataverseUserTemplate();
                user.SystemUserId = GetMessageString(userData, "systemuserid");
                user.AzureObjectId = GetMessageString(userData, "azureobjectid");
                user.FullName = GetMessageString(userData, "fullname");
                user.Email = GetMessageString(userData, "email");
                user.DomainName = GetMessageString(userData, "domainname");
                user.IsDisabled = GetMessageBool(userData, "userdisabled");
                user.BusinessUnitName = GetMessageString(userData, "businessunitname");
                user.BusinessUnitDisabled = GetMessageBool(userData, "businessunitdisabled");
                user.AppAccessKnown = GetMessageBool(userData, "appaccessknown");
                user.HasAppAccess = GetMessageBool(userData, "hasappaccess");
                user.AppAccessReason = GetMessageString(userData, "appaccessreason");

                if (string.IsNullOrWhiteSpace(user.SystemUserId))
                {
                    continue;
                }

                var status = "Ready";
                if (user.IsDisabled)
                {
                    status = "User off";
                }
                else if (user.BusinessUnitDisabled)
                {
                    status = "BU off";
                }
                else if (string.IsNullOrWhiteSpace(user.AzureObjectId))
                {
                    status = "No Entra ID";
                }
                else if (user.AppAccessKnown && !user.HasAppAccess)
                {
                    status = "No app access";
                }
                else if (!user.AppAccessKnown)
                {
                    status = "Access ?";
                }

                var rowIndex = userGrid.Rows.Add(user.FullName, user.Email, status);
                userGrid.Rows[rowIndex].Tag = user;

                var statusToolTip = user.AppAccessReason ?? string.Empty;
                if (string.IsNullOrWhiteSpace(user.AzureObjectId))
                {
                    statusToolTip =
                        "This Dataverse user has no Microsoft Entra object ID. " +
                        "Dataverse Impersonator requires an Entra-backed user and will not allow impersonation.";
                }
                userGrid.Rows[rowIndex].Cells[2].ToolTipText = statusToolTip;

                if (user.IsDisabled ||
                    user.BusinessUnitDisabled ||
                    string.IsNullOrWhiteSpace(user.AzureObjectId) ||
                    (user.AppAccessKnown && !user.HasAppAccess))
                {
                    userGrid.Rows[rowIndex].DefaultCellStyle.ForeColor = Color.Gray;
                }
                else if (!user.AppAccessKnown)
                {
                    userGrid.Rows[rowIndex].DefaultCellStyle.ForeColor = Color.DarkGoldenrod;
                }

                count++;
            }
        }

        searchStatusLabel.Text = count == 0
            ? "No matching users found."
            : count + " user(s) found. Ready = can impersonate. No Entra ID / No app access / BU off / User off = unavailable. Access ? = app access could not be verified.";
        impersonateButton.Enabled = !impersonationEnabled && CanImpersonateUser(GetSelectedUser());
    }

    private void HandleIdentityMessage(Dictionary<string, object> data)
    {
        if (!MessageSucceeded(data))
        {
            HandleIdentityError(GetMessageString(data, "error"));
            return;
        }

        var source = GetMessageString(data, "source");
        var userId = GetMessageString(data, "userid");
        var fullName = GetMessageString(data, "fullname");
        var email = GetMessageString(data, "email");
        var domainName = GetMessageString(data, "domainname");

        var verified = false;
        if (impersonationEnabled && impersonatedUser != null)
        {
            // Xrm/WhoAmI reflects the authenticated browser user in this scenario,
            // not the effective Dataverse caller used by the model-driven app.
            // Automatic impersonation verification is handled separately by the app-shell check.
            return;
        }
        else
        {
            currentUserLabel.Text = BuildUserDisplay(fullName, email, domainName);
            SetStatus("NORMAL CONTEXT", Color.DarkGreen);
        }

        if (showVerificationResult)
        {
            showVerificationResult = false;

            string text;
            if (!impersonationEnabled)
            {
                text =
                    "Current model-driven app user: " + fullName + ".\r\n\r\n" +
                    "UserId: " + userId +
                    "\r\nVerification source: " + (string.IsNullOrWhiteSpace(source) ? "Xrm client context" : source);
            }
            else if (verified)
            {
                text =
                    "Verified. The model-driven app is running as " + impersonatedUser.FullName + ".\r\n\r\n" +
                    "UserId: " + userId + "\r\n" +
                    "Verification source: Xrm.Utility.getGlobalContext().userSettings\r\n" +
                    "Header method: " + GetImpersonationHeaderName() + "\r\n" +
                    "WebView2 requests modified: " + webViewModifiedRequestCount;
            }
            else
            {
                text =
                    "The model-driven app user context did not match the selected user.\r\n\r\n" +
                    "Current app UserId: " + userId + "\r\n" +
                    "Expected UserId: " + (impersonatedUser == null ? "" : impersonatedUser.SystemUserId) + "\r\n\r\n" +
                    "Verification source: Xrm.Utility.getGlobalContext().userSettings\r\n" +
                    "Header method: " + GetImpersonationHeaderName() + "\r\n" +
                    "WebView2 requests modified: " + webViewModifiedRequestCount;
            }

            MessageBox.Show(
                text,
                "Current app user verification",
                MessageBoxButtons.OK,
                verified || !impersonationEnabled ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
        }
    }

    private void HandleIdentityError(string error)
    {
        if (!string.IsNullOrWhiteSpace(error) &&
            error.IndexOf("model-driven app user context is not available yet", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            if (!impersonationEnabled)
            {
                currentUserLabel.Text = "The model-driven app user context is still loading.";
                SetStatus("NORMAL CONTEXT", Color.DarkGreen);
            }
            showVerificationResult = false;
            return;
        }

        currentUserLabel.Text = "Could not read the model-driven app user context.";

        if (impersonationEnabled)
        {
            return;
        }

        SetStatus("NORMAL CONTEXT", Color.DarkGreen);

        UpdateInjectionStatus();

        if (showVerificationResult)
        {
            showVerificationResult = false;
            MessageBox.Show(
                FriendlyDataverseError(error) +
                "\r\n\r\nHeader method: " + (impersonationEnabled ? GetImpersonationHeaderName() : "none") +
                "\r\nWebView2 requests modified: " + webViewModifiedRequestCount,
                "Current app user verification failed",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private string FriendlyDataverseError(string error)
    {
        if (string.IsNullOrWhiteSpace(error))
        {
            return "Dataverse returned an unknown error.";
        }

        if (error.IndexOf("business unit", StringComparison.OrdinalIgnoreCase) >= 0 &&
            error.IndexOf("disabled", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return "Dataverse received the impersonation request, but the selected user's business unit is disabled. " +
                   "That user cannot build a model-driven app/UCI security context until the business unit is enabled or the user is moved to an enabled business unit.\r\n\r\n" +
                   error;
        }

        if (error.IndexOf("user", StringComparison.OrdinalIgnoreCase) >= 0 &&
            error.IndexOf("is disabled", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return "Dataverse received the impersonation request, but the selected Dataverse user is disabled.\r\n\r\n" + error;
        }

        if (error.IndexOf("HTTP 403", StringComparison.OrdinalIgnoreCase) >= 0 ||
            error.IndexOf("ActOnBehalfOfAnotherUser", StringComparison.OrdinalIgnoreCase) >= 0 ||
            error.IndexOf("prvActOnBehalfOfAnotherUser", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return "Dataverse rejected the request. Your account may be missing the Act on Behalf of Another User (prvActOnBehalfOfAnotherUser) privilege.\r\n\r\n" + error;
        }

        if (error.IndexOf("502", StringComparison.OrdinalIgnoreCase) >= 0 ||
            error.IndexOf("RetrieveUserContext", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return "The impersonation request reached the model-driven app, but the app could not build the selected user's UCI user context. " +
                   "Check whether the selected user and their business unit are enabled and whether the user can access this app.\r\n\r\n" + error;
        }

        return error;
    }

    private string BuildUserDisplay(string fullName, string email, string domainName)
    {
        var name = string.IsNullOrWhiteSpace(fullName) ? "Unknown user" : fullName;
        var secondary = !string.IsNullOrWhiteSpace(email) ? email : domainName;
        return string.IsNullOrWhiteSpace(secondary) ? name : name + "\r\n" + secondary;
    }

    private bool CanImpersonateUser(DataverseUserTemplate user)
    {
        if (user == null)
        {
            return false;
        }

        if (user.IsDisabled || user.BusinessUnitDisabled)
        {
            return false;
        }

        if (string.IsNullOrWhiteSpace(user.AzureObjectId))
        {
            return false;
        }

        if (user.AppAccessKnown && !user.HasAppAccess)
        {
            return false;
        }

        return true;
    }

    private DataverseUserTemplate GetSelectedUser()
    {
        if (userGrid.SelectedRows.Count == 0)
        {
            return null;
        }

        return userGrid.SelectedRows[0].Tag as DataverseUserTemplate;
    }

    private async Task StartImpersonationAsync()
    {
        if (!initialized || impersonationEnabled)
        {
            return;
        }

        var user = GetSelectedUser();
        if (user == null)
        {
            MessageBox.Show("Select a user first.", "No user selected", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (user.IsDisabled)
        {
            MessageBox.Show(
                "This Dataverse user is disabled and cannot load a model-driven app security context.",
                "User is disabled",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        if (user.BusinessUnitDisabled)
        {
            var businessUnit = string.IsNullOrWhiteSpace(user.BusinessUnitName)
                ? "the user's business unit"
                : "business unit '" + user.BusinessUnitName + "'";

            MessageBox.Show(
                "This user cannot be impersonated because " + businessUnit + " is disabled.\r\n\r\n" +
                "Dataverse rejects the user's UCI context before the app can load. Choose a user in an enabled business unit.",
                "Business unit is disabled",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        if (string.IsNullOrWhiteSpace(user.AzureObjectId))
        {
            MessageBox.Show(
                "This Dataverse user cannot be impersonated because the user record does not have a Microsoft Entra object ID.\r\n\r\n" +
                "Dataverse Impersonator only allows Entra-backed users and uses CallerObjectId for impersonation. " +
                "Select another user or correct the Dataverse/Entra user mapping first.",
                "User has no Microsoft Entra ID",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        if (user.AppAccessKnown && !user.HasAppAccess)
        {
            MessageBox.Show(
                "This user cannot be impersonated in the current model-driven app because they do not have access to this app.\r\n\r\n" +
                (string.IsNullOrWhiteSpace(user.AppAccessReason)
                    ? "The user is not associated with a security role assigned to this app."
                    : user.AppAccessReason) +
                "\r\n\r\nGive the user access to this app, then search again.",
                "User does not have app access",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        if (!user.AppAccessKnown)
        {
            var continueAnswer = MessageBox.Show(
                "The tool could not verify whether this user has access to the current model-driven app.\r\n\r\n" +
                (string.IsNullOrWhiteSpace(user.AppAccessReason) ? string.Empty : user.AppAccessReason + "\r\n\r\n") +
                "Continue with impersonation anyway?",
                "App access could not be verified",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning);

            if (continueAnswer != DialogResult.Yes)
            {
                return;
            }
        }

        var answer = MessageBox.Show(
            "Impersonate " + user.FullName + "?\r\n\r\n" +
            "The app will reload. Actions you perform can create, modify, or delete real Dataverse records using the impersonated security context.",
            "Start impersonation",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning);

        if (answer != DialogResult.Yes)
        {
            return;
        }

        if (privilegeCheckSucceeded && !hasDirectImpersonationPrivilege)
        {
            MessageBox.Show(
                "Your current Dataverse account does not have the directly assigned " +
                "Act on Behalf of Another User (prvActOnBehalfOfAnotherUser) privilege.\r\n\r\n" +
                "Microsoft requires this privilege, or a role containing it, to be assigned directly to your user. " +
                "Team-inherited privileges do not qualify.\r\n\r\n" +
                "Assign the built-in Delegate security role directly to your user, or add the privilege to another directly assigned role.",
                "Impersonation privilege missing",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        searchTimer.Stop();
        searchBox.Enabled = false;
        searchButton.Enabled = false;
        impersonateButton.Enabled = false;
        stopButton.Enabled = false;

        // Test through the same network-level interception path used for the full app.
        // Page-level fetch headers can be altered by the app/service-worker path and are not equivalent to Level Up.
        await BeginNetworkImpersonationAsync(user, false);
    }

    private async Task PrepareShellForNewImpersonationAsync()
    {
        if (webView.CoreWebView2 == null)
        {
            needsCleanShellOnNextImpersonation = false;
            return;
        }

        identityTimer.Stop();

        try
        {
            webView.CoreWebView2.Stop();
        }
        catch
        {
        }

        try
        {
            webView.CoreWebView2.Navigate("about:blank");
            await Task.Delay(160);
        }
        catch
        {
        }

        try
        {
            var dataKinds =
                CoreWebView2BrowsingDataKinds.AllDomStorage |
                CoreWebView2BrowsingDataKinds.DiskCache |
                CoreWebView2BrowsingDataKinds.BrowsingHistory;

            await webView.CoreWebView2.Profile.ClearBrowsingDataAsync(dataKinds);
        }
        catch
        {
            // Preserve cookies/SSO even if selective cleanup is unavailable on an older runtime.
        }

        await Task.Delay(120);
        needsCleanShellOnNextImpersonation = false;
        UpdateBrowserNavigationButtons();
    }

    private async Task StopImpersonationAsync()
    {
        if (!initialized || !impersonationEnabled)
        {
            return;
        }

        impersonationEnabled = false;
        await DisableCdpInterceptionAsync();
        impersonatedUser = null;
        usingLegacyHeader = false;
        cdpModifiedRequestCount = 0;
        webViewModifiedRequestCount = 0;
        autoVerifyAttemptCount = 0;
        autoVerificationConfirmed = false;

        searchBox.Enabled = true;
        searchButton.Enabled = true;
        stopButton.Enabled = false;
        impersonateButton.Enabled = GetSelectedUser() != null;
        SetStatus("STOPPING IMPERSONATION", Color.DarkGoldenrod);
        currentUserLabel.Text = "Reloading normal context...";
        UpdateInjectionStatus();

        // Stop means return to the real signed-in caller.  Do not reuse the impersonated
        // model-driven-app browser state: clear this isolated profile and rebuild the exact page
        // only after header injection has been disabled.
        var targetUrl = GetCurrentDataversePageUrl();
        await ResetBrowserContextAsync(targetUrl);

        // The next impersonation should rebuild Power Apps' client-side shell so the top-right
        // account/avatar changes with the newly selected user instead of remaining on the caller.
        needsCleanShellOnNextImpersonation = true;
    }

    private string GetCurrentDataversePageUrl()
    {
        Uri uri;

        if (webView.Source != null &&
            webView.Source.IsAbsoluteUri &&
            webView.Source.Scheme == Uri.UriSchemeHttps &&
            LooksLikeDataverseHost(webView.Source.Host))
        {
            return webView.Source.AbsoluteUri;
        }

        if (Uri.TryCreate(browserUrlBox.Text, UriKind.Absolute, out uri) &&
            uri.Scheme == Uri.UriSchemeHttps &&
            LooksLikeDataverseHost(uri.Host))
        {
            return uri.AbsoluteUri;
        }

        return appUrl;
    }

    private async Task ResetBrowserContextAsync(string targetUrl)
    {
        if (string.IsNullOrWhiteSpace(targetUrl) || webView.CoreWebView2 == null)
        {
            return;
        }

        identityTimer.Stop();

        try
        {
            webView.CoreWebView2.Stop();
        }
        catch
        {
        }

        // Leave the model-driven app document before clearing its browser state.
        try
        {
            webView.CoreWebView2.Navigate("about:blank");
            await Task.Delay(180);
        }
        catch
        {
        }

        // Each impersonator window already owns an isolated WebView2 user-data folder.
        // Clearing that isolated profile on every identity transition prevents cached UCI,
        // service-worker, cookie and DOM-storage state from leaking across users.
        try
        {
            await webView.CoreWebView2.Profile.ClearBrowsingDataAsync();
        }
        catch
        {
            // Older WebView2 runtimes may not expose every clear-data capability.
            // The blank-document teardown still provides a safe fallback.
        }

        await Task.Delay(180);
        webView.CoreWebView2.Navigate(targetUrl);
    }

    private void SetStatus(string text, Color color)
    {
        statusLabel.Text = text;
        statusLabel.ForeColor = color;
        Text = "Dataverse Impersonator - " + text;
    }
}
'@

$references = @(
    'System.dll',
    'System.Core.dll',
    'System.Drawing.dll',
    'System.Windows.Forms.dll',
    'System.Web.Extensions.dll',
    $coreDll,
    $winFormsDll
)

# Use a unique internal type name on every run. This keeps the public script versionless
# and also lets an updated copy be run again in the same PowerShell ISE session.
$typeSuffix = 'B' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
$userTypeName = 'DataverseUser_' + $typeSuffix
$formTypeName = 'DataverseImpersonatorForm_' + $typeSuffix
$sourceToCompile = $source.Replace('DataverseUserTemplate', $userTypeName).Replace('DataverseImpersonatorFormTemplate', $formTypeName)
Add-Type -TypeDefinition $sourceToCompile -Language CSharp -ReferencedAssemblies $references -IgnoreWarnings

$settingsFolder = Join-Path $env:LOCALAPPDATA 'DataverseImpersonator'
New-Item -ItemType Directory -Path $settingsFolder -Force | Out-Null

$sessionRoot = Join-Path $settingsFolder 'Sessions'
New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
Get-ChildItem -LiteralPath $sessionRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

[System.Windows.Forms.Application]::EnableVisualStyles()

$resolvedAppUrl = $null

if (-not [string]::IsNullOrWhiteSpace($LaunchUri)) {
    try {
        $resolvedAppUrl = ConvertFrom-DataverseImpersonatorUri -UriText $LaunchUri
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Dataverse Impersonator - Invalid bookmarklet launch',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }
}
while ([string]::IsNullOrWhiteSpace($resolvedAppUrl)) {
    $enteredUrl = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Paste the full URL of the model-driven app/environment you want to open.',
        'Dataverse Impersonator - Choose Environment',
        ''
    )

    if ([string]::IsNullOrWhiteSpace($enteredUrl)) {
        return
    }

    $resolvedAppUrl = Get-NormalizedDataverseUrl -Url $enteredUrl
    if (-not $resolvedAppUrl) {
        [System.Windows.Forms.MessageBox]::Show(
            'Please paste a full HTTPS Dataverse/model-driven app URL on dynamics.com.',
            'Invalid URL',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
}

$form = New-Object -TypeName $formTypeName -ArgumentList @($resolvedAppUrl, $settingsFolder)
[System.Windows.Forms.Application]::Run($form)
}
