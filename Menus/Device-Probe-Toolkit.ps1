# ==================================================================
# Filename: Device-Probe-Toolkit.ps1
# Description: Main script for the PC Maintenance and Utility Menu,
# which relies on the InteractiveMenu.psm1 module.
# ==================================================================
# ==================================================================
#region * Script Configuration and State *
# ==================================================================
# Define global script variables used by functions and menu actions
$Script:StartTime = Get-Date
$Script:OutputRoot = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'Output'
$Script:TcpTimeoutMs = 1500 # 1.5 second timeout for TCP connections/probes
$Script:HttpTimeoutSeconds = 4 # 4 second timeout for HTTP requests
$Script:LastResults = $null # Stores the result of the last task for export
# Ensure Output directory exists
if (-not (Test-Path $Script:OutputRoot)) { New-Item -ItemType Directory -Path $Script:OutputRoot | Out-Null }
#endregion
# ==================================================================
#region * Import Interactive Menu Module *
# ==================================================================
# Set the path to the InteractiveMenu.psm1 module located in the parent directory
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
# Assume the module is one level up relative to the Menus folder
$MenuModule = Join-Path (Split-Path $ScriptPath -Parent) 'InteractiveMenu.psm1'

if (Test-Path $MenuModule) {
    . $MenuModule
    Write-Host "[OK] InteractiveMenu.psm1 module loaded." -ForegroundColor Green
} else {
    Write-Error "InteractiveMenu.psm1 not found at '$MenuModule'. Exiting."
    return
}
#endregion
# ==================================================================
#region * Core Functions *
# ==================================================================
function New-SessionFolder {
    $stamp = $Script:StartTime.ToString('yyyyMMdd_HHmmss')
    $dir = Join-Path $Script:OutputRoot $stamp
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    return $dir
}

function Log-Write {
    param([string]$Message)
    $time = (Get-Date).ToString('s')
    Write-Host "[$time] $Message"
}

function Save-Json {
    param($Object, [string]$Path)
    $Object | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
}

function Save-CsvSafe {
    param($Object, [string]$Path)
    try { $Object | Export-Csv -Path $Path -NoTypeInformation -Force } catch { $Object | Out-File $Path -Encoding UTF8 }
}
#endregion
# ==================================================================
#region * Network * Discovery *
# ==================================================================
function Get-LocalIPv4Subnet {
    $ips = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Ethernet*','Wi-Fi*','WiFi*' -ErrorAction SilentlyContinue |
           Where-Object { $_.PrefixLength -and $_.IPAddress -and -not ($_.IPAddress -like '169.*') } |
           Select-Object -First 1
    if (-not $ips) {
        # fallback: try all interfaces
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $ips) { throw "No IPv4 address found on local machine." }
    $prefix = $ips.PrefixLength
    $ip = [System.Net.IPAddress]::Parse($ips.IPAddress)
    $mask = [System.Net.IPAddress]::Parse((([System.Net.IPNetwork]::Parse("$($ips.IPAddress)/$prefix")).Netmask).ToString())
    return @{ IP = $ips.IPAddress; Prefix = $prefix }
}

function Ping-Sweep {
    param([string]$NetworkCidr)
    Log-Write "Starting ping sweep on $NetworkCidr (ICMP and ARP)"
    $alive = @()
    try {
        # Use Test-Connection in parallel-ish batches
        $addresses = (1..254) | ForEach-Object { ($NetworkCidr -replace '/\d+$','').Split('.')[0..2] -join '.' } # placeholder
    } catch {}
    # Simpler: use arp-scan like approach using Test-NetConnection per address in the /24 of local IP
    $local = Get-LocalIPv4Subnet
    $base = ($local.IP.Split('.')[0..2] -join '.')
    $ips = 1..254 | ForEach-Object { "$base.$_" }
    $jobs = @()
    foreach ($t in $ips) {
        $jobs += [PSCustomObject]@{ IP = $t; Alive = $false }
    }
    $out = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    $ips | ForEach-Object -Parallel {
        param($ip, $bag, $timeout)
        try {
            # Use the global $Script:TcpTimeoutMs for the Test-NetConnection timeout
            $r = Test-NetConnection -ComputerName $ip -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($r) { $bag.Add([PSCustomObject]@{IP=$ip; Alive=$true}) } else { $bag.Add([PSCustomObject]@{IP=$ip; Alive=$false}) }
        } catch { $bag.Add([PSCustomObject]@{IP=$ip; Alive=$false}) }
    } -ArgumentList $out, $Script:TcpTimeoutMs
    $alive = $out.Where{ $_.Alive } | Sort-Object IP
    return $alive
}

function Quick-NmapLikePortScan {
    param([string]$ip, [int[]]$ports)
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $ports) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        # Use the global $Script:TcpTimeoutMs for connection timeout
        $async = $tcp.BeginConnect($ip, $p, $null, $null)
        $wait = $async.AsyncWaitHandle.WaitOne($Script:TcpTimeoutMs)
        if ($wait -and $tcp.Connected) {
            $tcp.EndConnect($async)
            $tcp.Close()
            $result.Add([PSCustomObject]@{ IP=$ip; Port=$p; Open=$true })
        } else {
            $tcp.Close()
            $result.Add([PSCustomObject]@{ IP=$ip; Port=$p; Open=$false })
        }
    }
    return $result
}
#endregion
# ==================================================================
#region * SSDP (basic) *
# ==================================================================
function Discover-SSDP {
    param([int]$TimeoutSec = 4)
    $mreq = [System.Text.Encoding]::ASCII.GetBytes(
        "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: ""ssdp:discover""`r`nMX: 2`r`nST: ssdp:all`r`n`r`n")
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.Client.ReceiveTimeout = $TimeoutSec * 1000
        $udp.EnableBroadcast = $true
        $udp.Connect("239.255.255.250",1900)
        $udp.Send($mreq, $mreq.Length) | Out-Null
        $responses = @()
        $end = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $end) {
            try {
                $remote = $udp.Receive([ref]$remoteEP)
                $s = [System.Text.Encoding]::ASCII.GetString($remote)
                $responses += $s
            } catch { break }
        }
        return $responses | Sort-Object -Unique
    } finally {
        $udp.Close()
    }
}
#endregion
# ==================================================================
#region * HTTP probing *
# ==================================================================
function Get-HttpInfo {
    param([string]$ip, [int]$port = 80)
    $uri = if ($port -eq 443) { "https://$ip" } else { "http://$ip:$port" }
    $timeout = New-TimeSpan -Seconds $Script:HttpTimeoutSeconds
    try {
        $resp = Invoke-WebRequest -Uri $uri -Method Head -UseBasicParsing -TimeoutSec $Script:HttpTimeoutSeconds -ErrorAction Stop
        $headers = $resp.Headers
        return [PSCustomObject]@{ IP=$ip; Port=$port; Url=$uri; StatusCode = $resp.StatusCode; Headers = $headers }
    } catch {
        return [PSCustomObject]@{ IP=$ip; Port=$port; Url=$uri; Error = $_.Exception.Message }
    }
}

function Try-CommonFirmwareEndpoints {
    param([string]$ip, [int[]]$ports = @(80,443,8080))
    $candidates = @(
        "/backup", "/backup.tar", "/backup.bin", "/firmware", "/firmware.bin",
        "/update", "/cgi-bin/firmware", "/sys/firmware", "/admin/firmware",
        "/download/firmware", "/fwupdate"
    )
    $results = @()
    $sessionDir = New-SessionFolder
    foreach ($p in $ports) {
        foreach ($c in $candidates) {
            $schema = if ($p -eq 443) { "https" } else { "http" }
            $u = "$schema://$ip`:$p$c"
            try {
                $r = Invoke-WebRequest -Uri $u -Method Get -TimeoutSec $Script:HttpTimeoutSeconds -UseBasicParsing -ErrorAction Stop
                $len = ($r.RawContentLength -as [int]) -or ($r.Content.Length -as [int])
                $fn = Join-Path $sessionDir ("http_$($ip)_$($p)_" + ($c.TrimStart('/') -replace '[\/\?]','_') + ".bin")
                $r.Content | Out-File -FilePath $fn -Encoding Byte -ErrorAction SilentlyContinue
                $results += [PSCustomObject]@{ IP=$ip; Port=$p; Endpoint=$c; Status=$r.StatusCode; Length=$len; Saved=$fn }
            } catch {
                $results += [PSCustomObject]@{ IP=$ip; Port=$p; Endpoint=$c; Error = $_.Exception.Message }
            }
        }
    }
    return $results
}
#endregion
# ==================================================================
#region * Insert Files *
# ==================================================================
#region --- Probe ---
$probe = @"
<?xml version='1.0' encoding='UTF-8'?>
<e:Envelope xmlns:e='http://www.w3.org/2003/05/soap-envelope'
            xmlns:w='http://schemas.xmlsoap.org/ws/2004/08/addressing'
            xmlns:d='http://schemas.xmlsoap.org/ws/2005/04/discovery'>
    <e:Header>
        <w:MessageID>uuid:$uuid</w:MessageID>
        <w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
        <d:Types>dn:NetworkVideoTransmitter</d:Types>
    </e:Header>
    <e:Body>
        <d:Probe/>
    </e:Body>
</e:Envelope>
"@
#endregion
# ------------------------------------------------------------------
#region --- Soap ---
$soap = @"
<?xml version='1.0' encoding='utf-8'?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV='http://www.w3.org/2003/05/soap-envelope'
 xmlns:tds='http://www.onvif.org/ver10/device/wsdl'>
    <SOAP-ENV:Body>
        <tds:GetDeviceInformation/>
    </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
"@
#endregion
# ------------------------------------------------------------------
#endregion
# ==================================================================
#region * SNMP and ONVIF Extensions * Requires: optional 'snmpwalk'
# ==================================================================
function Test-ExternalTool {
    param([string]$Tool)
    $p = Get-Command $Tool -ErrorAction SilentlyContinue
    return $null -ne $p
}

function Get-SNMPInfo {
    param(
        [string]$Target,
        [string]$Community = 'public',
        [int]$TimeoutSec = 5
    )
    $out = [PSCustomObject]@{
        Target = $Target
        Method = $null
        Results = @()
        Error = $null
        Timestamp = (Get-Date).ToString('s')
    }

    if (Test-ExternalTool -Tool 'snmpwalk') {
        $out.Method = 'snmpwalk'
        try {
            $cmd = "snmpwalk -v2c -c $Community -t $TimeoutSec $Target"
            $raw = & snmpwalk -v2c -c $Community -t $TimeoutSec $Target 2>&1
            $out.Results = $raw
        } catch {
            $out.Error = $_.Exception.Message
        }
        return $out
    }

    # Best-effort fallback: query standard SNMP sysDescr OID (1.3.6.1.2.1.1.1.0) using a minimal UDP packet
    $out.Method = 'udpsnmp_minimal'
    try {
        # Minimal SNMPv2c GetRequest encoding is non-trivial to implement fully here.
        # Instead attempt to open a UDP socket and send a very small SRP-like crafted packet is unreliable.
        # We will attempt to use the built-in .NET UdpClient to test connectivity only.
        $udp = New-Object System.Net.Sockets.UdpClient
        $udp.Client.ReceiveTimeout = $TimeoutSec * 1000
        $udp.Connect($Target, 161)
        # Send an empty packet to test reachability (non-destructive). Real SNMP requires proper BER.
        $payload = [byte[]]@(0x30,0x00)   # empty BER SEQUENCE (invalid SNMP) but safe as probe
        $udp.Send($payload, $payload.Length) | Out-Null
        $remoteEP = New-Object System.Net.IPEndPoint([IPAddress]::Any,0)
        try {
            $resp = $udp.Receive([ref]$remoteEP)
            $out.Results += ("SNMP UDP responded {0} bytes from {1}" -f $resp.Length, $remoteEP.Address)
        } catch {
            $out.Results += "No SNMP UDP response (port 161) - device may not run SNMP or filtered"
        } finally {
            $udp.Close()
        }
    } catch {
        $out.Error = $_.Exception.Message
    }
    return $out
}


function Discover-ONVIF {
    # ONVIF discovery via WS-Discovery (UDP multicast 3702)
    param([int]$TimeoutSeconds = 4)
    # WS-Discovery Probe message (simple SOAP envelope). MessageID should be unique.
    $uuid = [Guid]::NewGuid().ToString()
    $probe
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($probe)
    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
    $multicastEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse("239.255.255.250"), 3702)
    $udp.EnableBroadcast = $true
    $udp.Client.ReceiveTimeout = $TimeoutSeconds * 1000
    try {
        $udp.Send($bytes, $bytes.Length, $multicastEP) | Out-Null
        $end = (Get-Date).AddSeconds($TimeoutSeconds)
        $responses = @()
        while ((Get-Date) -lt $end) {
            try {
                $remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any,0)
                $resp = $udp.Receive([ref]$remoteEP)
                $s = [System.Text.Encoding]::UTF8.GetString($resp)
                $responses += [PSCustomObject]@{ From = $remoteEP.Address.ToString(); Raw = $s }
            } catch { break }
        }
        return $responses | Sort-Object -Property From -Unique
    } finally {
        $udp.Close()
    }
}

function Get-ONVIFDeviceInfo {
    param(
        [string]$ServiceUrl = "http://{0}/onvif/device_service",
        [string]$TargetHost,
        [string]$Username = $null,
        [string]$Password = $null,
        [int]$TimeoutSec = 8
    )
    if (-not $TargetHost) { throw "Provide -TargetHost (IP or host) or explicit ServiceUrl" }
    $service = if ($ServiceUrl -like "*{0}*") { $ServiceUrl -f $TargetHost } else { $ServiceUrl }
    $soap
    $headers = @{ 'Content-Type' = 'application/soap+xml; charset=utf-8' }
    $creds = $null
    if ($Username -and $Password) { $creds = New-Object System.Management.Automation.PSCredential($Username,(ConvertTo-SecureString $Password -AsPlainText -Force)) }
    try {
        $invokeParams = @{
            Uri = $service
            Method = 'Post'
            Body = $soap
            Headers = $headers
            TimeoutSec = $TimeoutSec
            UseBasicParsing = $true
            ErrorAction = 'Stop'
        }
        if ($creds) { $invokeParams['Credential'] = $creds }
        $r = Invoke-WebRequest @invokeParams
        $xml = [xml]$r.Content
        # Parse common ONVIF device info fields
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsMgr.AddNamespace('d', 'http://www.onvif.org/ver10/device/wsdl')
        $manufacturer = $xml.SelectSingleNode('//Manufacturer')?.InnerText
        $model = $xml.SelectSingleNode('//Model')?.InnerText
        $fw = $xml.SelectSingleNode('//FirmwareVersion')?.InnerText
        $serial = $xml.SelectSingleNode('//SerialNumber')?.InnerText
        $hardware = $xml.SelectSingleNode('//HardwareId')?.InnerText
        return [PSCustomObject]@{
            Service = $service
            Manufacturer = $manufacturer
            Model = $model
            Firmware = $fw
            Serial = $serial
            HardwareId = $hardware
            RawXml = $xml.OuterXml
        }
    } catch {
        return [PSCustomObject]@{ Service = $service; Error = $_.Exception.Message }
    }
}
#endregion
# ==================================================================
#region * Serial (USB-TTL) banner reader *
# ==================================================================
function Read-SerialPortBanner {
    param(
        [string]$ComPort,
        [int[]]$BaudRates = @(115200, 57600, 9600),
        [int]$ReadTimeoutMs = 3000
    )
    $results = @()
    foreach ($b in $BaudRates) {
        try {
            $sp = New-Object System.IO.Ports.SerialPort $ComPort, $b, 'None', 8, 'One'
            $sp.ReadTimeout = $ReadTimeoutMs
            $sp.Open()
            Start-Sleep -Milliseconds 300
            $buf = ''
            try {
                $buf = $sp.ReadExisting()
            } catch { $buf = '' }
            $sp.Close()
            $results += [PSCustomObject]@{ Port = $ComPort; Baud = $b; Banner = $buf }
        } catch {
            $results += [PSCustomObject]@{ Port = $ComPort; Baud = $b; Error = $_.Exception.Message }
        }
    }
    return $results
}
#endregion
# ==================================================================
#region * Define Menu Items *
# ==================================================================
$MenuItems = @(
    [PSCustomObject]@{  Id      = '1'; Name = 'Discover hosts (ping sweep)';                         Enabled = $true
                        Key     = '1'
                        Help    = 'Pings all 254 potential hosts in your local /24 subnet.'
                        Type    = 'Network'
                        Action  = {
                            $local = Get-LocalIPv4Subnet
                            $cidr = "$($local.IP)/24" # Assuming /24 for simplification of sweep
                            Log-Write "Scanning local subnet (determined as $($cidr)) for live hosts..."
                            $results = Ping-Sweep
                            $script:LastResults = $results
                            Write-Host "`nFound $($results.Count) hosts alive on the subnet." -ForegroundColor Yellow
                            $results | Format-Table -AutoSize
                            Pause
                        } },
    [PSCustomObject]@{  Id      = '2'; Name = 'SSDP discovery (UPnP/SSDP)';                          Enabled = $true
                        Key     = '2'
                        Help    = 'Listen for multicast UPnP responses (printers, smart devices, etc.).'
                        Type    = 'Network'
                        Action  = {
                            Log-Write "Performing SSDP (UPnP) M-SEARCH discovery (4 second timeout)..."
                            $results = Discover-SSDP
                            $script:LastResults = $results
                            Write-Host "`nFound $($results.Count) raw SSDP responses." -ForegroundColor Yellow

                            # Simple extraction of 'LOCATION' headers
                            $locations = $results | Select-String 'LOCATION: (.*)' | ForEach-Object { $_.Matches.Groups[1].Value.Trim() } | Sort-Object -Unique
                            if ($locations.Count -gt 0) {
                                Write-Host "`n--- Extracted Unique Locations ---" -ForegroundColor Cyan
                                $locations | Format-Table -AutoSize -Wrap
                            }
                            Pause
                        } },
    [PSCustomObject]@{  Id      = '3'; Name = 'Probe ports on a host (quick TCP)';                   Enabled = $true
                        Key     = '3'
                        Help    = 'Performs a simple TCP connection test on specified ports of a target IP.'
                        Type    = 'Network'
                        Action  = {
                            $ip = Read-Host "Enter target IP address (e.g., 192.168.1.1)"
                            $ports = Read-Host "Enter ports to scan (comma-separated, e.g., 21,22,80,443)"
                            $portArray = $ports -split ',' | ForEach-Object { [int]::TryParse($_, [ref]$null) | Out-Null; [int]$_ } | Where-Object { $_ -gt 0 }
                            if (-not $ip -or -not $portArray) { Log-Write "Invalid input."; Pause; return }

                            Log-Write "Starting quick TCP port scan on $ip for ports: $($portArray -join ',')..."
                            $results = Quick-NmapLikePortScan -ip $ip -ports $portArray
                            $script:LastResults = $results
                            Write-Host "`n--- Open Ports on $ip ---" -ForegroundColor Cyan
                            $results | Where-Object { $_.Open } | Select-Object IP, Port, Open | Format-Table -AutoSize
                            Pause
                        } },
    [PSCustomObject]@{  Id      = '4'; Name = 'HTTP header probe + fetch common firmware endpoints'; Enabled = $true
                        Key     = '4'
                        Help    = 'Checks HTTP headers (Server, Content-Type) and tries common paths for firmware images.'
                        Type    = 'HTTP'
                        Action  = {
                            $ip = Read-Host "Enter target IP address (e.g., 192.168.1.1)"
                            $port = Read-Host "Enter HTTP port (e.g., 80, 443, 8080. Leave blank for 80)"
                            $port = [int]::TryParse($port, [ref]$null) | Out-Null; $port = $port -gt 0 ? $port : 80
                            if (-not $ip) { Log-Write "Invalid IP."; Pause; return }

                            Log-Write "Performing HTTP probe on $ip:$port..."
                            $headers = Get-HttpInfo -ip $ip -port $port
                            Write-Host "`n--- HTTP Header Probe ($($headers.Url)) ---" -ForegroundColor Cyan
                            $headers | Select-Object IP, Port, StatusCode, Url, Error | Format-Table -AutoSize
                            if ($headers.Headers) { $headers.Headers | Format-List }

                            Log-Write "`nAttempting to fetch common firmware endpoints..."
                            $firmwareResults = Try-CommonFirmwareEndpoints -ip $ip -ports @($port)
                            $script:LastResults = $firmwareResults
                            Write-Host "`n--- Firmware Endpoint Results ---" -ForegroundColor Cyan
                            $firmwareResults | Select-Object IP, Port, Endpoint, Status, Length, Saved, Error | Format-Table -AutoSize -Wrap
                            Write-Host "`nRaw output saved to: $($Script:OutputRoot) (check subfolders)" -ForegroundColor Green
                            Pause
                        } },
    [PSCustomObject]@{  Id      = '5'; Name = 'Export last session results (JSON/CSV)';              Enabled = $true
                        Key     = '5'
                        Help    = 'Saves the output from the last executed task (1-4) to disk.'
                        Type    = 'Utility'
                        Action  = {
                            if (-not $script:LastResults) {
                                Write-Host "No results from the current session found in memory to export." -ForegroundColor Yellow
                                Pause; return
                            }
                            $sessionDir = New-SessionFolder
                            $jsonPath = Join-Path $sessionDir 'last_results.json'
                            $csvPath = Join-Path $sessionDir 'last_results.csv'

                            Save-Json -Object $script:LastResults -Path $jsonPath
                            Save-CsvSafe -Object $script:LastResults -Path $csvPath

                            Write-Host "Successfully saved last results (type: $($script:LastResults.GetType().Name)) to:" -ForegroundColor Green
                            Write-Host "JSON: $jsonPath"
                            Write-Host "CSV: $csvPath"
                            Pause
                        } },
    [PSCustomObject]@{  Id      = '6'; Name = 'Guidance: Serial (USB-TTL) extraction (notes)';       Enabled = $true
                        Key     = '6'
                        Help    = 'Provides a quick guide on how to safely connect and interact with serial headers.'
                        Type    = 'Guidance'
                        Action  = {
                            Write-Host @"
============================================================
Serial (USB-TTL) Extraction Guidance
============================================================
1. **Identify Headers:** Locate 3 to 5 unpopulated pin headers (typically 4 or 6 pins) near the main CPU/flash chip.
2. **Find GND:** Use a multimeter to find a pin that has continuity with the ground plane (usually the metal shield of USB/Ethernet ports).
3. **Identify RX/TX (Data):**
   - **TX (Transmit):** Output from the Device.
   - **RX (Receive):** Input to the Device.
   - The TX pin will usually show a rapid fluctuation in voltage/data during boot.
4. **Determine Voltage (CRITICAL):** Measure the voltage of the potential VCC pin relative to GND. **NEVER connect the power pin (VCC) from your USB-TTL adapter to the device's VCC.** Only use VCC to measure the logic level (e.g., 3.3V or 1.8V). Set your USB-TTL adapter to match this voltage.
5. **Connect:** Connect only **GND** (device to adapter), **RX** (device) to **TX** (adapter), and **TX** (device) to **RX** (adapter).
6. **Use Terminal:** Use a terminal program (or the 'Read-SerialPortBanner' function with a COM port) on a common baud rate (9600, 57600, 115200) to capture the boot loader banner.
"@ -ForegroundColor Yellow
                            Pause
                        } },
    [PSCustomObject]@{ Id    = '0'; Name = 'Quit Menu';                             Enabled = $true
                       Key   = 'Q'
                       Help  = 'Exit menu'
                       Type  = 'Meta'
                       Action  = { return 'quit' } }
)
#endregion
# ==================================================================
#region * Run Menu *
# ==================================================================
# Explicitly define the desired menu title
$MenuTitleExplicit = "Device & Network Probe Toolkit v1.0"

if (-not [string]::IsNullOrWhiteSpace($MenuTitleExplicit)) {
    $FinalMenuTitle = $MenuTitleExplicit
} else {
    $FinalMenuTitle = Get-MenuTitle
    Write-Verbose "No explicit menu title defined. Falling back to title derived from Get-MenuTitle: '$FinalMenuTitle'."
}

if (Get-Command -Name Show-InteractiveMenu -ErrorAction SilentlyContinue) {
    Show-InteractiveMenu -MenuData $MenuItems -MenuTitle $FinalMenuTitle
} else {
    Write-Error "The Show-InteractiveMenu function was not loaded from InteractiveMenu.psm1. Cannot run menu."
}
#endregion
