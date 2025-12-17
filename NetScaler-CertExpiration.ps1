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

# If you need TLS11, keep it; otherwise prefer TLS12 only.
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls11,Tls12'

$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$Credential     = New-Object System.Management.Automation.PSCredential ($Username, $SecurePassword)

$Session = $null
$xmlOut  = $null

try {
    # Connect
    $Session = Connect-Netscaler -Hostname $Nsip -Credential $Credential -PassThru -Https:$true -ErrorAction Stop

    # Get certs
    $CertResults = Get-NSSSLCertificate -Session $Session -ErrorAction Stop

    # FIXED filter (your original -or "SRVR_CERT" is always true)
    $CertResults = $CertResults | Where-Object {
        ($_.certificatetype -match 'CLNT_CERT') -or
        ($_.certificatetype -match 'SRVR_CERT') -or
        ($_.certificatetype -match 'INTM_CERT')
    }

    # Compute earliest expiry
    $FirstExpiration = [int]::MaxValue
    foreach ($Result in $CertResults) {
        $d = [int]$Result.daystoexpiration
        if ($d -lt $FirstExpiration) { $FirstExpiration = $d }
    }
    if ($FirstExpiration -eq [int]::MaxValue) { $FirstExpiration = 0 }

    # IMPORTANT: Disconnect BEFORE producing XML (prevents junk after </prtg>)
    try { Disconnect-Netscaler -Session $Session -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
    $Session = $null

    # Build XML once
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<prtg>")

    [void]$sb.AppendLine("  <result>")
    [void]$sb.AppendLine("    <channel>Next Cert Expiration</channel>")
    [void]$sb.AppendLine("    <value>$FirstExpiration</value>")
    [void]$sb.AppendLine("    <unit>Custom</unit>")
    [void]$sb.AppendLine("    <CustomUnit>Days</CustomUnit>")
    [void]$sb.AppendLine("    <LimitMode>1</LimitMode>")
    [void]$sb.AppendLine("    <LimitMinWarning>30</LimitMinWarning>")
    [void]$sb.AppendLine("    <LimitWarningMsg>Certificate expiration in less than 30 days</LimitWarningMsg>")
    [void]$sb.AppendLine("    <LimitMinError>10</LimitMinError>")
    [void]$sb.AppendLine("    <LimitErrorMsg>Certificate expiration in less than 10 days</LimitErrorMsg>")
    [void]$sb.AppendLine("  </result>")

    foreach ($Result in $CertResults) {
        # Keep channel name XML-safe
        $ch = [string]$Result.certkey
        $ch = $ch -replace '&','and' -replace '[<>]',''

        [void]$sb.AppendLine("  <result>")
        [void]$sb.AppendLine("    <channel>$ch</channel>")
        [void]$sb.AppendLine("    <value>$([int]$Result.daystoexpiration)</value>")
        [void]$sb.AppendLine("    <unit>Custom</unit>")
        [void]$sb.AppendLine("    <CustomUnit>Days</CustomUnit>")
        [void]$sb.AppendLine("    <LimitMode>1</LimitMode>")
        [void]$sb.AppendLine("    <LimitMinWarning>30</LimitMinWarning>")
        [void]$sb.AppendLine("    <LimitWarningMsg>Certificate expiration in less than 30 days</LimitWarningMsg>")
        [void]$sb.AppendLine("    <LimitMinError>10</LimitMinError>")
        [void]$sb.AppendLine("    <LimitErrorMsg>Certificate expiration in less than 10 days</LimitErrorMsg>")
        [void]$sb.AppendLine("  </result>")
    }

    [void]$sb.AppendLine("  <error>0</error>")
    [void]$sb.AppendLine("  <text>Certs checked: $($CertResults.Count)</text>")
    [void]$sb.AppendLine("</prtg>")

    $xmlOut = $sb.ToString()
}
catch {
    $msg = $_.Exception.Message -replace '&','and' -replace '[<>]',''
    $xmlOut = "<prtg><error>1</error><text>NetScaler cert check failed: $msg</text></prtg>"
}
finally {
    # Best-effort disconnect (but do not print anything)
    try {
        if ($Session) { Disconnect-Netscaler -Session $Session -Force -ErrorAction SilentlyContinue | Out-Null }
    } catch {}
}

Write-Output $xmlOut