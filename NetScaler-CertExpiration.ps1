Param(
	[string]$Nsip,
	[string]$Username,
	[string]$Password
)
    
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($Username, $SecurePassword)

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

$Session =  Connect-Netscaler -Hostname $Nsip -Credential $Credential -PassThru -Https:$true

$CertResults = Get-NSSSLCertificate -session $Session | Where-Object {$_.certificatetype -contains "CLNT_CERT" -or "SRVR_CERT" -or "INTM_CERT"}

$FirstExpiration = 2000
foreach ($Result in $CertResults) {
	If ($Result.daystoexpiration -lt $FirstExpiration) {$FirstExpiration=$Result.daystoexpiration}
}

Write-Host "<prtg>"

Write-Host "<result>"
Write-Host "<channel>Next Cert Expiration</channel>"
Write-Host ("<value>" + $FirstExpiration + "</value>")
Write-Host "<unit>Custom</unit>"
Write-Host "<CustomUnit>Days</CustomUnit>"
Write-Host "<LimitMode>1</LimitMode>"
Write-Host "<LimitMinWarning>30</LimitMinWarning>"
Write-Host "<LimitWarningMsg>Certificate expiration in less than 30 days</LimitWarningMsg>"
Write-Host "<LimitMinError>10</LimitMinError>"
Write-Host "<LimitErrorMsg>Certificate expiration in less than 10 days</LimitErrorMsg>"
Write-Host "</result>"

foreach ($Result in $CertResults) {
	Write-Host "<result>"
	Write-Host ("<channel>" + $Result.certkey + "</channel>")
	Write-Host ("<value>" + $Result.daystoexpiration + "</value>")
	Write-Host "<unit>Custom</unit>"
	Write-Host "<CustomUnit>Days</CustomUnit>"
	Write-Host "<LimitMode>1</LimitMode>"
	Write-Host "<LimitMinWarning>30</LimitMinWarning>"
	Write-Host "<LimitWarningMsg>Certificate expiration in less than 30 days</LimitWarningMsg>"
	Write-Host "<LimitMinError>10</LimitMinError>"
	Write-Host "<LimitErrorMsg>Certificate expiration in less than 10 days</LimitErrorMsg>"
	Write-Host "</result>"
}

Write-Host "</prtg>"

Disconnect-Netscaler
