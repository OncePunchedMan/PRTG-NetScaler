Param(
    [string]$Nsip,
    [string]$Username,
    [string]$Password
)

$ErrorActionPreference      = 'Stop'
$WarningPreference          = 'SilentlyContinue'
$VerbosePreference          = 'SilentlyContinue'
$InformationPreference      = 'SilentlyContinue'
$ProgressPreference         = 'SilentlyContinue'

function Escape-Xml([string]$s) {
    if ($null -eq $s) { return "" }
    return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "'","&apos;")
}

function State-To-LookupValue([string]$state) {
    switch ($state) {
        'UP'             { return 1 }
        'DOWN'           { return 2 }
        'OUT OF SERVICE' { return 3 }
        default          { return 0 } # unknown
    }
}

# Disable SSL certificate validation (as in your original)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$Credential     = New-Object System.Management.Automation.PSCredential ($Username, $SecurePassword)

$Session = $null
$xmlOut  = $null

try {
    # Connect
    $Session = Connect-Netscaler -Hostname $Nsip -Credential $Credential -PassThru -Https:$true -ErrorAction Stop

    # Query vServers
    $CSvServerResults  = Get-NSCSVirtualServer  -Session $Session -ErrorAction Stop
    $LBvServerResults  = Get-NSLBVirtualServer  -Session $Session -ErrorAction Stop
    $VPNvServerResults = Get-NSVPNVirtualServer -Session $Session -ErrorAction Stop
    $AAAvServerResults = Get-NSAAAVirtualServer -Session $Session -ErrorAction Stop

    # Disconnect BEFORE output to avoid any junk after </prtg>
    try { Disconnect-Netscaler -Session $Session -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
    $Session = $null

    # Build XML once
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<prtg>")

    # CS vServers: State
    foreach ($Result in $CSvServerResults) {
        $stateVal = State-To-LookupValue $Result.curstate
        $name     = Escape-Xml ([string]$Result.name)

        [void]$sb.AppendLine("  <result>")
        [void]$sb.AppendLine("    <channel>State CS: $name</channel>")
        [void]$sb.AppendLine("    <value>$stateVal</value>")
        [void]$sb.AppendLine("    <unit>Custom</unit>")
        [void]$sb.AppendLine("    <CustomUnit>Status</CustomUnit>")
        [void]$sb.AppendLine("    <valuelookup>prtg.networklookups.REST.NetscalerVserverStatus</valuelookup>")
        [void]$sb.AppendLine("  </result>")
    }

    # LB vServers: State + Health (skip http_redirect)
    foreach ($Result in $LBvServerResults) {
        if ($Result.name -like '*http_redirect') { continue }

        $stateVal = State-To-LookupValue $Result.curstate
        $name     = Escape-Xml ([string]$Result.name)

        [void]$sb.AppendLine("  <result>")
        [void]$sb.AppendLine("    <channel>State LB: $name</channel>")
        [void]$sb.AppendLine("    <value>$stateVal</value>")
        [void]$sb.AppendLine("    <unit>Custom</unit>")
        [void]$sb.AppendLine("    <CustomUnit>Status</CustomUnit>")
        [void]$sb.AppendLine("    <valuelookup>prtg.networklookups.REST.NetscalerVserverStatus</valuelookup>")
        [void]$sb.AppendLine("  </result>")

        # Some modules return health as string; normalize to integer percent
        $health = 0
        try { $health = [int]$Result.health } catch { $health = 0 }

        [void]$sb.AppendLine("  <result>")
        [void]$sb.AppendLine("    <channel>Health LB: $name</channel>")
        [void]$sb.AppendLine("    <value>$health</value>")
        [void]$sb.AppendLine("    <unit>Percent</unit>")
        [void]$sb.AppendLine("  </result>")
    }

    # VPN vServers: State
    foreach ($Result in $VPNvServerResults) {
        $stateVal = State-To-LookupValue $Result.curstate
        $name     = Escape-Xml ([string]$Result.name)

        [void]$sb.AppendLine("  <result>")
        [void]$sb.AppendLine("    <channel>State VPN: $name</channel>")
        [void]$sb.AppendLine("    <value>$stateVal</value>")
        [void]$sb.AppendLine("    <unit>Custom</unit>")
        [void]$sb.AppendLine("    <CustomUnit>Status</CustomUnit>")
        [void]$sb.AppendLine("    <valuelookup>prtg.networklookups.REST.NetscalerVserverStatus</valuelookup>")
        [void]$sb.AppendLine("  </result>")
    }

    # AAA vServers: State
    foreach ($Result in $AAAvServerResults) {
        $stateVal = State-To-LookupValue $Result.curstate
        $name     = Escape-Xml ([string]$Result.name)

        [void]$sb.AppendLine("  <result>")
        [void]$sb.AppendLine("    <channel>State AAA: $name</channel>")
        [void]$sb.AppendLine("    <value>$stateVal</value>")
        [void]$sb.AppendLine("    <unit>Custom</unit>")
        [void]$sb.AppendLine("    <CustomUnit>Status</CustomUnit>")
        [void]$sb.AppendLine("    <valuelookup>prtg.networklookups.REST.NetscalerVserverStatus</valuelookup>")
        [void]$sb.AppendLine("  </result>")
    }

    [void]$sb.AppendLine("  <error>0</error>")
    [void]$sb.AppendLine("  <text>CS:$($CSvServerResults.Count) LB:$($LBvServerResults.Count) VPN:$($VPNvServerResults.Count) AAA:$($AAAvServerResults.Count)</text>")
    [void]$sb.AppendLine("</prtg>")

    $xmlOut = $sb.ToString()
}
catch {
    $msg = Escape-Xml $_.Exception.Message
    $xmlOut = "<prtg><error>1</error><text>NetScaler vServer check failed: $msg</text></prtg>"
}
finally {
    # Best effort disconnect, never emit output
    try {
        if ($Session) { Disconnect-Netscaler -Session $Session -Force -ErrorAction SilentlyContinue | Out-Null }
    } catch {}
}

Write-Output $xmlOut