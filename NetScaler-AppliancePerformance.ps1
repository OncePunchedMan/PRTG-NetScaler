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

# Disable SSL certificate validation
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls11,Tls12'

$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$Credential     = New-Object System.Management.Automation.PSCredential ($Username, $SecurePassword)

$Session = $null
$xmlOut  = $null

try {
    $Session = Connect-Netscaler -Hostname $Nsip -Credential $Credential -PassThru -Https:$true -ErrorAction Stop

    $ResultSSL       = Get-NSStat -Session $Session -Type 'ssl'      -ErrorAction Stop
    $ResultSystem    = Get-NSStat -Session $Session -Type 'system'   -ErrorAction Stop
    $ResultInterface = Get-NSStat -Session $Session -Type 'interface'-ErrorAction Stop

    # Disconnect BEFORE output to avoid junk after </prtg>
    try { Disconnect-Netscaler -Session $Session -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
    $Session = $null

    # Helpers for safe math
    function Safe-Percent([double]$used, [double]$size) {
        if (-not $size -or $size -le 0) { return 0 }
        return [math]::Truncate(($used / $size) * 100)
    }

    # RX/TX totals
    $rxbytesratetotal = 0
    $txbytesratetotal = 0
    foreach ($i in $ResultInterface) {
        $rxbytesratetotal += [double]$i.rxbytesrate
        $txbytesratetotal += [double]$i.txbytesrate
    }

    $cpu     = [math]::Round([double]$ResultSystem.cpuusagepcnt)
    $pktcpu  = [math]::Round([double]$ResultSystem.pktcpuusagepcnt)
    $mgmtcpu = [math]::Round([double]$ResultSystem.mgmtcpuusagepcnt)
    $mem     = [math]::Round([double]$ResultSystem.memusagepcnt)

    # memuseinmb -> BytesMemory (PRTG expects bytes)
    $memBytes = ([int64]$ResultSystem.memuseinmb) * 1024 * 1024

    $disk0 = Safe-Percent ([double]$ResultSystem.disk0used) ([double]$ResultSystem.disk0size)
    $disk1 = Safe-Percent ([double]$ResultSystem.disk1used) ([double]$ResultSystem.disk1size)

    $sslRate = [double]$ResultSSL.ssltransactionsrate

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<prtg>")

    [void]$sb.AppendLine("  <result><channel>CPU Usage</channel><value>$cpu</value><unit>Percent</unit></result>")
    [void]$sb.AppendLine("  <result><channel>Packet CPU Usage</channel><value>$pktcpu</value><unit>Percent</unit></result>")
    [void]$sb.AppendLine("  <result><channel>Management CPU Usage</channel><value>$mgmtcpu</value><unit>Percent</unit></result>")
    [void]$sb.AppendLine("  <result><channel>Memory Usage</channel><value>$mem</value><unit>Percent</unit></result>")

    [void]$sb.AppendLine("  <result><channel>Memory MB Usage</channel><value>$memBytes</value><unit>BytesMemory</unit></result>")

    [void]$sb.AppendLine("  <result><channel>Disk 0 Usage</channel><value>$disk0</value><unit>Percent</unit></result>")
    [void]$sb.AppendLine("  <result><channel>Disk 1 Usage</channel><value>$disk1</value><unit>Percent</unit></result>")

    [void]$sb.AppendLine("  <result><channel>SSL Transactions/sec</channel><value>$sslRate</value><unit>Custom</unit><CustomUnit>Transactions</CustomUnit></result>")

    [void]$sb.AppendLine("  <result><channel>RX Bandwidth</channel><value>$rxbytesratetotal</value><unit>BytesBandwidth</unit><SpeedSize>KiloBits</SpeedSize></result>")
    [void]$sb.AppendLine("  <result><channel>TX Bandwidth</channel><value>$txbytesratetotal</value><unit>BytesBandwidth</unit><SpeedSize>KiloBits</SpeedSize></result>")

    [void]$sb.AppendLine("  <error>0</error>")
    [void]$sb.AppendLine("  <text>System/SSL/Interface stats OK</text>")
    [void]$sb.AppendLine("</prtg>")

    $xmlOut = $sb.ToString()
}
catch {
    $msg = Escape-Xml $_.Exception.Message
    $xmlOut = "<prtg><error>1</error><text>NetScaler stats check failed: $msg</text></prtg>"
}
finally {
    try {
        if ($Session) { Disconnect-Netscaler -Session $Session -Force -ErrorAction SilentlyContinue | Out-Null }
    } catch {}
}

Write-Output $xmlOut
