#Axel Soebert - 1SNB_D2A - algemeenASo.psm1

# 1 herbruikbare helperfunctie. verantwoordelijk voor het weergeven van alle menu's en input te regelen.
function Show-Menu {
    <#
    .SYNOPSIS
        Toont een menu en geeft de gebruikersinput terug.
    
    .DESCRIPTION
        Deze helperfunctie geeft een menu weer met een decoratieve titel en een array van opties.
        Voegt automatisch een 'Q: back / Quit' optie toe onderaan.
        Geeft de ingevoerde keuze terug als string aan de aanroepende functie.
    
    .PARAMETER Title
        De titel die bovenaan het menu wordt meegegeven.
    
    .PARAMETER MenuOptions
        Array van strings met de weer te geven menu-opties.
        Lege strings in de array worden gebruikt als scheidingslijnen.
    
    .EXAMPLE
        $Keuze = Show-menu -Titel "Hoofdmenu -MenuOptions @("1: optie1", "2: optie2", ...)"
    
    #>
    param(
        [string]$Title,
        [string[]]$MenuOptions   # array van opties om te weergeven.
    )

    Clear-Host
    
    $TitleDecoration = "    " + ("~" * ($Title.Length))

    Write-Host $TitleDecoration -ForegroundColor Blue
    Write-Host "    $Title"          -ForegroundColor Blue
    Write-Host $TitleDecoration -ForegroundColor Blue
    Write-Host ""

    foreach ($option in $MenuOptions) {
        Write-Host "    $option"
    }

    Write-Host "`n    Q: Back / Quit" -ForegroundColor Red
    return (Read-Host -Prompt "`n    Choice").Trim()
}

function Invoke-BasicConfigMenu {
    <#
    .SYNOPSIS
        Toont het basisconfigmenu en verwerkt de gebruikersinput.
    
    .DESCRIPTION
        Geeft een herhalend menu weer met opties over basisconfiguratie:
            -Computernaam via xml
            -Computernaam manual
            -netwerk config via xml
            -mappen aanmaken
            -shares aanmaken
            -permissies instellen voor mappen en shares,
    .EXAMPLE
        Invoke-BasicConfigMenu
    
    #>
    do {
        $ChoiceMenu = Show-Menu -Title "Basic Config" -MenuOptions @(
            "1: Rename computer (with automatic restart. Input via included XML file.)",
            "2: Set computername manually",
            "",
            "3: Set network adapter properties (via XML file)",
            "4: Set network Adapter properties [manual]",
            "",
            "5: Show computerInfo",
            "6: Show Network Adapter Information",
            "",
            "7: Full Windows update with reboot.",
            "8: Interactive console"
        )
        switch ($ChoiceMenu) {
            '1' { Set-ComputerName }
            '2' {
                $PCName = Read-Host -Prompt "   New ComputerName"        
                Set-ComputerName -PCName $PCName
            }
            '3' { Set-NetAdapterProperties }
            '4' { Set-NetAdapterProperties -Manual}
            '5' {Get-ComputerInfo; Read-Host -Prompt "`nEnter to continue"}
            '6' {Get-NetAdapter | format-list; Read-Host -Prompt "`nEnter to continue"}
            '7' {Start-WindowsUpdate}
            '8' {$Host.EnterNestedPrompt()}
            'Q' {}
            Default { Write-Host "`n    Invalid choice." -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
        }
    } while (($ChoiceMenu).ToUpper() -ne 'Q')
}

function Invoke-ClientConfigMenu {
    <#
    .SYNOPSIS
        Toont het basisconfigmenu en verwerkt de gebruikersinput.
    
    .DESCRIPTION
        Geeft een herhalend menu weer met opties voor client specifieke configuratie.
        momenteel ondersteunt dit menu enkel een simpele Join-Domain functie.
        Het menu blijft herhalen tot de gebruiker 'Q' kiest.
    
    .EXAMPLE
        Invoke-ClientConfigMenu
    
    #>
    do {
        $ChoiceMenu = Show-Menu -Title "Basic Config" -MenuOptions @(
            "1: Join Domain",
            "2: Interactive console"
        )

        switch ($ChoiceMenu) {
            '1' {
                Join-Domain
            }
            '2' {$Host.EnterNestedPrompt()}
            'Q' {}
            Default { Write-Host "`n    Invalid choice." -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
        }
    } while (($ChoiceMenu).ToUpper() -ne 'Q')      
}

Function Set-ComputerName {
    <#
    .SYNOPSIS
        Past de computernaam aan en herstart automatisch.
    
    .DESCRIPTION
        Hernoemt de computer naar een opgegeven naam of naar de naam uit Computer.Settings.xml. Configureert eerst autologon en runonce zodat het menu
        na automatische herstart wordt hervat. Als de computer al de gekozen naam heeft, wordt de naamweiziging overgeslagen en toont het een melding.
        Alle acties worden weggeschreven naar het log-bestand.
    
    .PARAMETER SettingsPath
        Pad naar het XML-bestand. Standaard: 'settings\Computer.Settings.xml'
    
    .PARAMETER PCName
        Nieuwe computernaam. Als deze opgegeven word, wordt de xml niet gelezen.
    
    .EXAMPLE
        Set-ComputerName
    .EXAMPLE
        Set-ComputerName -PCName "test123"
    #>
    param(
        #valt terug op default value uit xml file als de gebruiker niets meegeeft
        [string]$SettingsPath = "settings\Computer.Settings.xml",
        [string]$PCName
    )
    try {
        if ($PCName) {
            $newname = $PCName
        }
        else {
            [xml]$Settings = Get-Content $SettingsPath -ErrorAction Stop
            $newname = $Settings.Settings.name
        }

        $CurrentName = $env:COMPUTERNAME

        if ($CurrentName -eq $newname) {
            Write-Log -Message "Computername was already '$newname', skipping the rename"
            Write-Host "    [!] Computer name is already '$newName', skipping the rename." -ForegroundColor Yellow
            Start-Sleep -Seconds 2

        }
        else {
            Enter-RunOnce
            Enter-AutoLogin
            Write-Log -Message "Renaming computer from '$Currentname' to '$newname'."
            Rename-Computer -NewName $newName -Force
            write-log -Message "Rename '$CurrentName' to '$newname' successful."
            Restart-Computer -Force
        }

    }
    catch [System.UnauthorizedAccessException] {
        Write-Host "    [!] ERROR: You dont have permissions to Rename '$CurrentName'"
        Start-Sleep -Seconds 2
        Write-Log -Message "ERROR in Set-ComputerName: $($_.exception.message)"
    }
    catch [System.IO.FileNotFoundException] {
        Write-Host  "    [!] ERROR: Can't read new name from XML because XML input file is not found."
        Start-Sleep -Seconds 2
        Write-Log -Message "ERROR in Set-ComputerName: $($_.exception.message)"
    }
    catch {
        Write-Host "    ERROR: $($_.exception.message)"
        start-sleep -Seconds 2
        Write-Log -Message "ERROR in Set-ComputerName: $($_.exception.message)"
    }
}

function Enter-RunOnce {
    <#
    .SYNOPSIS
        Registreert het hoofdscript in de runonce registry key als het script dat moet worden gerunt wanneer de gebruiker terug inlogd na een reboot.
    
    .DESCRIPTION
        Schrijft een RunOnce registersleutel weg zodat het Menu-Script automatisch opstart na reboot en login. 
        Wordt gebruikt in combinatie met Enter-AutoLogin om een onderbroken configuratie te hervatten na herstart.
    
    .PARAMETER scriptPath
        Pad naar het powershell script dat na de reboot moet worden uitgevoerd. Standaard: '.\MenuASo.ps1'
    
    .EXAMPLE
        Enter AutoLogin
    
    .EXAMPLE
        Enter-RunOnce -ScriptPath "C:\scripts\MenuASo.ps1"
    #>
    [CmdletBinding()]
    param (
        $scriptPath = ".\MenuASo.ps1"
    )
    try{
        $script = Resolve-Path $scriptPath
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
            -Name "ResumeTheMenu" `
            -Value "powershell.exe -ExecutionPolicy Bypass -File `"$script`""   
        }
    Catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        Write-Host "    [!] ERROR: You do not have permission to write/read to or from the registry"
        Write-Log -Message "ERROR in Enter-RunOnce: $($_.exception.message)"
    }
}

function Enter-AutoLogin {
    <#
    .SYNOPSIS
        Configureert automatische login na een reboot.
    
    .DESCRIPTION
        Schrijft de opgegeven credentials naar WinLogon in het registry zodat windows automatisch inlogt na een verplichte reboot.
        Bedoeld voor gebruik in functies met geplande reboots tijdens configuratie, zodat het script automatisch kan verderlopen, zonder handmatig te hoeven rebooten.
    
    .PARAMETER credential
        PSCredential object met gebruikersnaam en wachtwoord voor autologon.
    
    .EXAMPLE
        Enter-Autologin
    .EXAMPLE
        $Cred = Get-Credential
        Enter-AutoLogin -Credential $Cred
    #>
    [CmdletBinding()]
    param(
        [pscredential]$credential = (Get-Credential -Message "Enter credentials for autologin after reboot")
    )
    
    try {
        $plainPassword = $credential.GetNetworkCredential().Password
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

        Set-ItemProperty -Path $regPath -Name "AutoAdminLogon" -Value "1"
        Set-ItemProperty -Path $regPath -Name "DefaultUsername" -Value $credential.UserName
        Set-ItemProperty -Path $regPath -Name "DefaultPassword" -Value $plainPassword
        Write-Log -Message "Set Autologin for next reboot"
    }
    Catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        Write-Host "    [!] ERROR: You do not have permission to write/read to or from the registry"
        Write-Log -Message "ERROR in Enter-AutoLogin: $($_.exception.message)"
    }
}

function Clear-AutoLogin {
    <#
    .SYNOPSIS
        Verwijderd de autologon-instellingen uit de registry.
    
    .DESCRIPTION
        Zet AutoLogon terug op 0 en wist de inlog credentials uit WinLogon.
        Wordt elke keer na een reboot als eerste opgeroepen.
        Actie wordt weggeschreven naar het log bestand
    
    .EXAMPLE
        Clear-AutoLogin
    #>
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        Set-ItemProperty -Path $regPath -Name "AutoAdminLogon" -Value "0"
        Set-ItemProperty -Path $regPath -Name "DefaultUsername" -Value ""
        Set-ItemProperty -Path $regPath -Name "DefaultPassword" -Value ""
        Write-Log -Message "Succesfully cleared AutoLogin credentials."
    }
    Catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        Write-Host "    [!] ERROR: You do not have permission to write/read to or from the registry"
        start-sleep -Seconds 2
        Write-Log -Message "ERROR in Clear-AutoLogin: $($_.exception.message)"
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Schrijft een logmelding naar het logbestand met de tijd er bij.
    
    .DESCRIPTION
        Voegt een regel toe aan het logbestand met het formaat 'yyyy-MM-dd HH:mm:ss'.
        Maakt het logbestand opnieuw aan al de gebruiker het perongeluk verwijderd.
        Alle andere functies gebruiken write-log voor fout en succes statussen op te slagen in de log.
    
    .PARAMETER Message
        De tekst die weggeschreven wordt naar het logbestand.
    
    .PARAMETER LogFile
        Pad naar het logbestand. Standaard: 'logs\InstallatieLogASo.txt'
    
    .EXAMPLE
        Write-Log -Message "Script gestart."
    .EXAMPLE
        Write-Log -Message "Script gestart." -LogFile "C:\logs\mijnlog.txt"
    #>
    param (
        [string]$Message,
        [string]$LogFile = ".\logs\InstallatieLogASo.txt"
    )
    try {
        if (-not(Test-Path $LogFile)) {
            New-Item -ItemType File -Path $LogFile -Force | Out-Null
        }
        $Timestamp = get-date -Format "yyyy-MM-dd HH:mm:ss"
        $LogEntry = "$Timestamp $Message"

        Add-Content -Path $LogFile -Value $LogEntry   
    }
    catch [System.UnauthorizedAccessException] {
        Write-Host "    ERROR: No access to '$LogFile'." -ForegroundColor Red
        Start-Sleep -Seconds 2      
    }
    catch [System.IO.FileNotFoundException] {
        Write-Host "    ERROR: File '$LogFile' not found." -ForegroundColor Red
        start-sleep -Seconds 2
    }
    catch {
        Write-Host "    ERROR: Failed to write to '$LogFile': $($_.exception.Message)." -ForegroundColor Red
        start-sleep -Seconds 2
    }
}

function Set-NetAdapterProperties {
    <#
    .SYNOPSIS
        Configureert netwerkadapters via XMl-bestand of via manuele invoer.
    
    .DESCRIPTION
        In automatische modus (standaard): Leest adapterinstellingen uit Computer.Settings.xml en kopplet elke adapter op basis van de mac addressen in de xml aan fysieke adapters hun macaddressen op de pc of server.
        Hernoemt de adapter en stelt DHCP of een statische ip addres, subnetmasker, gateway en DNS in.
        In Manuele modus (-Manuel): Toont de beschikbare adapters op interfaceIndex, vraagt interactief om naam, DHCP aan of uit.
        Alle acties worden weggeschreven naar het log bestand.
    
    .PARAMETER SettingsPath
        Pad naar het XML-bestand. Standaard: 'settings\Computer.Settings.xml'
    
    .PARAMETER Manual
        Toggle om manuele invoermodus te activeren in plaats van automatisch via XML.
    
    .EXAMPLE
        Set-NetAdapterProperties
    .EXAMPLE
        Set-NetAdapterProperties -Manuel
    .EXAMPLE
        Set-NetAdapterProperties -SettingsPath "C:\scripts\settings\Computer.Settings.xml"
    #>
    param(
        [string]$SettingsPath = "settings\Computer.Settings.xml",
        [switch]$Manual
    )

    try {
        if ($Manual) {
            $AvailableAdapters = Get-NetAdapter
            Write-Host "    Available adapters:" -ForegroundColor Blue
            $AvailableAdapters | ForEach-Object {
                Write-Host "    [$($_.InterfaceIndex)] $($_.Name) - $($_.MacAddress)"
            }

            $Index = (Read-Host "  Enter adapter interface index").trim()
            $PhysAdapter = $AvailableAdapters | Where-Object { $_.InterfaceIndex -eq $Index }

            if (-not $PhysAdapter) {
                Write-Host "    [!] No adapter found with index '$Index'." -ForegroundColor Yellow
                return
            }

            $NewName = (Read-Host "  New adapter name (leave it empty to keep '$($PhysAdapter.Name)')").Trim()
            if ($NewName -ne '') {
                Rename-NetAdapter -Name $PhysAdapter.Name -NewName $NewName -ErrorAction SilentlyContinue
                $PhysAdapter = Get-NetAdapter -Name $NewName
            }

            $UseDHCP = (Read-Host "  Enable DHCP? (y/n)").Trim().ToLower()
            if ($UseDHCP -eq 'y') {
                Set-NetIPInterface -InterfaceAlias $PhysAdapter.Name -Dhcp Enabled
                Write-Log -Message "DHCP enabled on: $($PhysAdapter.Name)"
                Write-Host "    DHCP enabled on '$($PhysAdapter.Name)'." -ForegroundColor Green
            }
            else {
                $IP      = Read-Host "  IP Address"
                $Prefix  = Read-Host "  Subnet prefix length (example: 24)"
                $Gateway = Read-Host "  Default gateway ip"
                $DNS     = Read-Host "  DNS server ip"

                Get-NetIPAddress -InterfaceAlias $PhysAdapter.Name -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
                Get-NetRoute     -InterfaceAlias $PhysAdapter.Name -ErrorAction SilentlyContinue | Remove-NetRoute     -Confirm:$false

                New-NetIPAddress -InterfaceAlias $PhysAdapter.Name -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $Gateway | Out-Null
                Set-DnsClientServerAddress -InterfaceAlias $PhysAdapter.Name -ServerAddresses $DNS

                Write-Log -Message "Manually set IP config on adapter $($PhysAdapter.Name)"
                Write-Host "    Static IP configured on '$($PhysAdapter.Name)'." -ForegroundColor Green
                Read-Host -Prompt "    Enter to continue"
            }
        }
        elseif ($SettingsPath) {
            [xml]$XMLSettings = Get-Content -Path $SettingsPath
            $XmlAdapters = $XMLSettings.settings.networksettings.networkadapter

            foreach ($XmlAdapter in $XmlAdapters) {
                $PhysAdapter = Get-NetAdapter | Where-Object { $_.MacAddress -eq $XmlAdapter.macaddress }

                if (-not $PhysAdapter) {
                    Write-Host "    [!] Adapter with MAC '$($XmlAdapter.macaddress)' not found. Skipping." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }

                Rename-NetAdapter -Name $PhysAdapter.Name -NewName $XmlAdapter.name -ErrorAction SilentlyContinue

                if ($XmlAdapter.dhcpenabled -eq 'true') {
                    Set-NetIPInterface -InterfaceAlias $XmlAdapter.name -Dhcp Enabled
                    ipconfig /renew $XmlAdapter.name #Heb ik er in gestoken omdat de wan geen ip krijgt van dhcp tot ik een renew uitvoer
                    Write-Host "    DHCP configured on adapter: $($XmlAdapter.name)" -ForegroundColor Green
                    Write-Log -Message "DHCP enabled on: $($XmlAdapter.name)"
                }
                else {
                    Get-NetIPAddress -InterfaceAlias $XmlAdapter.name -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
                    Get-NetRoute     -InterfaceAlias $XmlAdapter.name -ErrorAction SilentlyContinue | Remove-NetRoute     -Confirm:$false

                    New-NetIPAddress -InterfaceAlias $XmlAdapter.name -IPAddress $XmlAdapter.ip -PrefixLength $XmlAdapter.prefixlength -DefaultGateway $XmlAdapter.gateway -ErrorAction SilentlyContinue | Out-Null
                    Set-DnsClientServerAddress -InterfaceAlias $XmlAdapter.name -ServerAddresses $XmlAdapter.dns
                    Write-Host "    Ip and dns config succeeded on adapter: $($XmlAdapter.name)" -ForegroundColor Green

                    Write-Log -Message "Set IP config on adapter $($XmlAdapter.name)"
                }
            }
            read-host -Prompt "`n    Enter to continue"
        }
    }
    catch {
        Write-Host "    Error: $($_.exception.message)" -ForegroundColor Red
        Write-Log -Message "ERROR in set-NetAdapterProperties: $($_.exception.message)"
        read-host -Prompt "    Enter to continue"
    }
}

function Add-Directory {
    <#
    .SYNOPSIS
        Maakt mappen aan op basis van de inhoud van een tekstbestand.
    
    .DESCRIPTION
        Leest mappen.txt regel per regel en maakt elke opgegeven map/directory aan.
        bestaande mappen worden overgeslagen met een foutmelding maar stoppen de uitvoering niet.
        Alle acties worden weggeschreven naar het log bestand.
    
    .PARAMETER DirectoryFilePath
        Pad naar het text bestand waar alle directories instaan. Standaard: "settings\mappen.txt"
    
    .EXAMPLE
        Add-directory
    .EXAMPLE
        Add-Directory -DirectoryFilePath "C:\settings\mappen.txt"
    #>
    param (
        $DirectoryFilePath = "settings\mappen.txt"
    )

    try {
        $FileContents = Get-Content -Path $DirectoryFilePath
        write-host "    creating directories from '$DirectoryFilePath'..." -ForegroundColor Green
        Start-Sleep -Seconds 1
        foreach ($item in $FileContents) {
            try {
                New-Item -ItemType Directory -Path "$item" -ErrorAction Stop | out-null
                Write-Host "    Successfully created $item" -ForegroundColor Green
                Write-Log -Message "Successfully created $item"
            }
            catch [System.IO.IOException] {
                Write-Host "    [!] ERROR: $($_.Exception.Message)" -ForegroundColor Red
                Write-Log -Message "ERROR in Add-Directory: $($_.Exception.Message)"
            }
        }
        read-host -Prompt "`n    Enter to continue"
    }
    catch [System.IO.FileNotFoundException] {
        write-host "    [!] ERROR: mappen.txt not found"
        write-log -Message "ERROR in Add-Directory: $($_.exception.message)"
        read-host -Prompt "`n    Enter to continue"
    }
    catch [System.UnauthorizedAccessException] {
        Write-Host "    [!] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Message "    ERROR in Add-Directory: $($_.Exception.Message)"
        read-host -Prompt "`n    Enter to continue"
    }
}

function Add-Shares {
    <#
    .SYNOPSIS
        Maakt SMB-shares aan op basis van een CSV-bestand.
    
    .DESCRIPTION
        Leest shares.csv met kolommen 'map' en 'share', gescheiden door ';'.
        Maakt de mappen aan als ze nog niet bestaan.
        Slaat een share over als die al bestaat en toont een melding.
        Alle acties worden weggeschreven naar het logbestand.
    
    .PARAMETER SharesCsv
        Pad naar het CSV-bestand met share informatie. Standaard: 'Settings\shares.csv'
    
    .EXAMPLE
        Add-Shares
    .EXAMPLE
        Add-Shares -ShareCsv "C:\scripts\settings\shares.csv"
    #>
    param (
        [string]$SharesCsv = "settings\shares.csv"
    )

    try {
        $Shares = import-csv -Path $SharesCsv -Delimiter ';'

        foreach ($share in $Shares) {
            $Dir = $share.map
            $Name = $Share.share

            if (-not (Test-Path $Dir)) {
                New-Item -ItemType Directory -Path $Dir -Force | Out-Null
                Write-Host "    Directory created: $Dir" -ForegroundColor Green
                Write-Log -Message "Directory created: $Dir"
            }

            $ShareExists = Get-SmbShare -Name $Name -ErrorAction SilentlyContinue

            if ($ShareExists) {
                Write-Host "    [!] Share skipped. share: $name already exists" -ForegroundColor Yellow
                Write-Log -Message "Share $Name skipped (already exists)."
            }
            else {
                New-SmbShare -Name $Name -Path $Dir -ErrorAction Stop | Out-Null
                Write-Host "    Share created: $Name --> $Dir" -ForegroundColor Green
                Write-Log -Message "Share created: $Name --> $Dir"
            }
        }
        read-host -Prompt "`n    Enter to continue"
        
    }
    catch [System.IO.FileNotFoundException] {
        Write-Host "    ERROR: shares.csv not found" -ForegroundColor Red
        Write-Log -Message "    ERROR in Add-Shares: $($_.exception.message)"
    }
    catch {
        Write-Host "    ERROR: $($_.exception.message)" -ForegroundColor Red
        Write-Log -Message "    ERROR in Add-Shares: $($_.exception.message)"
        read-host -Prompt "`n    Enter to continue"
    }  
}

function Add-Permissions {
    <#
    .SYNOPSIS
        Stelt NTFS- en Share-rechten in op basis van een CSV-bestand.
    
    .DESCRIPTION
        Leest rechten.csv met kolommen 'map', 'share', 'groep', 'NTFS_permission' en 'Share_permission', gescheiden door ';'.
        Controleert per rij of de map, share en lokale groep bestaan voor er permissies worden ingesteld. Ontbrekende onderdelen worden overgeslagen.
        Stelt NTFS-rechten in via ACL en share-rechten via Grant-SmbShareAccess.
        Alle acties worden weggeschreven naar het logbestand.

    .PARAMETER RechtenCsv
        Pad naar het CSV-bestand met rechten-informatie. Standaard: 'settings\rechten.csv'
    
    .EXAMPLE
        Add-Permissions
    
    .EXAMPLE
        Add-permissions -RechtenCsv "C:\scripts\settings\rechten.csv"
    #>
    param (
        [string]$RechtenCsv = "settings\rechten.csv"
    )
    
    try {
        $Rechten = Import-Csv -Path $RechtenCsv -Delimiter ';'

        foreach ($Entry in $Rechten) {
            $Dir = $Entry.map
            $ShareName = $Entry.share
            $Group = $Entry.groep
            $NtfsPermission = $entry.NTFS_permission
            $SharePermission = $entry.Share_permission

            #Checkt of de directory bestaat
            if (-not (Test-Path $Dir)) {
                Write-Host "    [!] Directory not found, skipping: $Dir" -ForegroundColor Yellow
                Write-Log -Message "Directory not found, skipping: $Dir"
                continue
            }

            #chekt of share bestaat
            $ShareExists = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
            if (-not $ShareExists) {
                Write-Host "    [!] Share not found, skipping: $ShareName" -ForegroundColor Yellow
                Write-Log -Message "Share not found, skipping: $ShareName"
                continue
            }

            #Chekt of security group bestaat
            $GroupExists = Get-LocalGroup -Name $Group -ErrorAction SilentlyContinue
            if (-not $GroupExists) {
                Write-Host "    [!] Group not found, skipping: $Group" -ForegroundColor Yellow
                Write-Log -Message "Group not found, skipping: $group"
                continue
            }

            #NTFS permisies
            $ACL = Get-Acl -Path $Dir
            $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule ($Group, $NtfsPermission, "ContainerInherit,ObjectInherit", "None", "Allow")
            $ACL.AddAccessRule($Rule)
            Set-Acl -Path $Dir -AclObject $ACL
            Write-Host "    NTFS permission set: $Group --> $Dir ($NtfsPermission)" -ForegroundColor Green
            Write-Log -Message "NTFS permission set: $Group --> $Dir ($NtfsPermission)"

            #Share permisies
            Grant-SmbShareAccess -Name $ShareName -AccountName $Group -AccessRight $SharePermission -Force | Out-Null
            Write-Host "    Share permission set: $group --> $ShareName ($SharePermission)" -ForegroundColor Green
            Write-Log -Message "    Share permission set: $Group --> $ShareName ($SharePermission)"
        }
        Read-Host -Prompt "`n    Enter to continue"
    }
    catch [System.IO.FileNotFoundException] {
        Write-Host "    ERROR: rechten.csv not found" -ForegroundColor Red
        Write-Log -Message "ERROR in Add-Permissions: $($_.exception.message)"
        Read-Host -Prompt "`n    Enter to continue"
    }
    catch {
        Write-Host "    ERROR: $($_.exception.message)" -ForegroundColor Red
        Write-Log -Message "ERROR in Add-Permissions: $($_.exception.message)"
        Read-Host -Prompt "`n    Enter to continue"
    }
}

function Start-WindowsUpdate {
    <#
    .SYNOPSIS
        Installeert Windows Updates en herstart automatisch het systeem.

    .DESCRIPTION
        Installeert alle beschikbare Windows Updates via PSWindowsUpdate.
        Configureert AutoLogin en RunOnce zodat het MenuScript automatisch hervat na reboot.
        Vereist de PSWindowsUpdate module.

    .PARAMETER ScriptPath
        Pad naar het hoofdscript dat na reboot hervat moet worden. Standaard: '.\MenuASo.ps1'

    .EXAMPLE
        Start-WindowsUpdateAndReboot
    #>

    try {
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Host "    PSWindowsUpdate module not found, installing..." -ForegroundColor Yellow
            Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser
        }

        Import-Module PSWindowsUpdate

        Enter-AutoLogin
        Enter-RunOnce

        $updates = Get-WindowsUpdate
        if (-not $updates) {
            Write-Host "    [i] No updates available, skipping reboot." -ForegroundColor Cyan
            Start-Sleep -Seconds 2
            return
        }

        Write-Host "    $($updates.Count) update(s) found" -ForegroundColor Green

        Write-Host "    Installing updates and rebooting..." -ForegroundColor Yellow
        Get-WindowsUpdate -Install -AcceptAll -AutoReboot

    } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        Write-Host "    [!] ERROR: Insufficient permissions to install updates or configure registry." -ForegroundColor Red
        Write-Log -Message "ERROR in Start-WindowsUpdate: $($_.exception.message)"
        Read-Host -Prompt "`n   Enter to continue"
    } catch {
        Write-Host "    [!] ERROR: $($_.exception.message)" -ForegroundColor Red
        Write-Log -Message "ERROR in Start-WindowsUpdate: $($_.exception.message)"
        Read-Host -Prompt "`n   Enter to continue"
    }
}

Export-ModuleMember -Function *
