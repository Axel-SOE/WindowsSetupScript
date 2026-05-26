#Axel Soebert - 1SNB_D2A
function Invoke-DomainConfigMenu {
    <#
    .SYNOPSIS
        Toont het domein configuratie menu en verwerkt de gebruiker zijn input.
    
    .DESCRIPTION
        Geeft een herhalend menu weer met opties voor domeinbeheer:
            - het installeren van een domeincontroller
            - aanmaken van OU's
            - securitygroups aanmaken
            - gebruikers toevoegen aan security groups
        Het menu blijft herhalen to de gebruiker q kiest. Dan gaat het terug naar het hoofdmenu.
    
    .EXAMPLE
        Invoke-DomainConfigMenu
    #>
    do {
        $ChoiceMenu = Show-Menu -Title "Basic Config" -MenuOptions @(
            "1: Install a domain controller",
            "2: Create OU's (via CSV file)",
            "3: Create Security groups (from CSV file)",
            "",
            "4: Create domain users (from JSON file)",
            "5: Add users to their securitygroups"
        )

        switch ($ChoiceMenu) {
            '1' { Install-DomainController }
            '2' {Add-OU}
            '3' {Add-SecurityGroups}
            '4' {Add-DomainUsers}
            '5' {Add-UsersToSecurityGroups}
            'Q' {}
            Default { Write-Host "`n    Invalid choice." -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
        }
    } while (($ChoiceMenu).ToUpper() -ne 'Q')
}

function Install-DomainController {
    <#
    .SYNOPSIS
        Installeert AD Domain Services en promoot de server naar domaincontroller.
    
    .DESCRIPTION
        lees domeininstellingen uit een xml-bestand. Installeert de AD-Domain-Services windows feature indien nodig. Zorgt ervoor dat de gebruiker terug automatisch aanmeld 
        na reboot en terecht komt in het hoofdmenu via autologin en runonce.
        Controleert daarna of het domein als bestaat:
            -Bestaat het domein al: dan wordt de server toegevoegd als extra deomaincontroller
            -Bestaat het domain niet: dan maakt het een nieuwe forest/domain aan
        Alle acties worden weggeschreven naar het log bestand via de write-log helper functie.
    
    .PARAMETER SettingsPath
        Pad naar het xml-configuratiebestand. Standaard: \settings\domain.settings.xml
    
    .EXAMPLE
        Install-DomainController
    .EXAMPLE
        Install-DomainController -SettingsPath "C:\scripts\settings\Domain.Settings.xml"
    #>
    param (
        $SettingsPath = "settings\Domain.Settings.xml"
    )
    try {
        [xml]$Settings = Get-Content $SettingsPath -ErrorAction Stop
        $Domain = $Settings.Settings.Domain

        # Installeer AD domain services als het nog niet geinstalleerd is.
        if ((Get-WindowsFeature AD-Domain-Services).InstallState -ne "Installed") {
            Write-Host "    Installing AD-Domain-Services..." -ForegroundColor Green
            Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
            Write-Log -Message "Installed AD-Domain-Services"
        }

        Enter-AutoLogin
        Enter-RunOnce

        #check of het domein al bestaat
        $DomainExists = $false
        try {
            get-ADDomain -Identity $Domain.domainname -ErrorAction stop | out-null
            $DomainExists = $true 
        }
        catch {
            $DomainExists = $false
        }

        if ($DomainExists) {
            Write-Host "   Domain '$($Domain.domainname)' already exists. Adding server as aditional domain controller..." -ForegroundColor Green
            start-sleep -Seconds 2
            Install-ADDSDomainController `
                -DomainName $Domain.domainname `
                -InstallDns:([bool]$Domain.IsDnsIncluded) `
                -force

            Write-Log -Message "Joined existing domain as aditional DC: $($Domain.domainname)"
        }
        else {
            #Domain niet gevonden. Maak nieuw domain.
            Write-Host "   Domain '$($Domain.domainname)' not found. Creating new forest..." -ForegroundColor Green
            Install-ADDSForest `
                -DomainName $Domain.domainname `
                -DomainNetBiosName $Domain.domainNetbiosName `
                -InstallDns:([bool]$Domain.IsDnsIncluded) `
                -Force

            Write-Log -Message "Created forest: $($Domain.domainname)"
        }
    }
    catch [System.IO.FileNotFoundException] {
        Write-Host "    ERROR: $($_.exception.message)"
        Write-Log "     ERROR in Install-DomainController: $($_.exception.message)"
        Read-Host -Prompt "    Enter to continue"
    }
    catch {
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Message "ERROR in Install-DomainController: $($_.Exception.Message)"
        Read-Host -Prompt "    Enter to continue"
    }
}

function Add-OU {
    <#
    .SYNOPSIS
        Maakt Organizational Units aan op basis van ous.csv.
    .DESCRIPTION
        Leest ous.csv met kolom naam en pad (afgebaakt door ';').
        Indien het OU al bestaat toont het een melding maar loop wel verder
        Alle acties worden weggeschreven naar de logfile door middel van de helper functie Write-Log

    .PARAMETER OuPath
        Pad naar ous.csv. Standaard: 'settings\ous.csv'
    .PARAMETER DomainRoot
        Naam van de Domain. Als er geen domainaam word meegegeven, haalt het script het op van de Server. bv. DomainName.local
    .EXAMPLE
        Add-OU
    .EXAMPLE
        Add-OU -OUPath "C:\scripts\settings\ous.csv"
    #>
    param (
        [string]$OuPath = "settings\ous.csv",
        [string]$DomainRoot = (Get-ADDomain).DistinguishedName
    )
    
    try {
        $OuTable = Import-Csv -Path $OuPath -Delimiter ';'
        Write-Host "`n    Creating ou's..." -ForegroundColor Green
        Write-Log -message "Attempting creation of organizational units..."

        foreach ($Row in $OuTable) {
            $Name = $Row.Name
            $Path = if ($Row.path) {$Row.Path.Trim()} else { "" }

            #bouwt parent DN op
            if ($path -ne "") {
                $ParentDN = (($path -split ",") | ForEach-Object { "OU=$_" }) -join ","
                $ParentDN = "$ParentDN,$DomainRoot"
            }
            else {
                $ParentDN = $DomainRoot
            }

            $TargetDN = "OU=$Name,$ParentDN"

            if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$TargetDN'" -ErrorAction SilentlyContinue) {
                Write-Host "    [!] OU already exists: $Name" -ForegroundColor Yellow
            }
            else {
                New-ADOrganizationalUnit -Name $Name -Path $ParentDN -ProtectedFromAccidentalDeletion $false
                Write-Host "    Created OU: $Name" -ForegroundColor Green
                Write-Log -message "Created OU '$Name' in '$ParentDN'"
            }
        }

        Read-Host -Prompt "`n    Enter to continue"
    }
    catch [System.IO.FileNotFoundException] {
        Write-Host "    [!] ERROR: ous.csv not found." -ForegroundColor Red
        Write-Log -message "ERROR in Add-OU: $($_.exception.message)"
        Read-Host -Prompt "    Enter to continue"
    }
    catch {
        Write-Host "    [!] ERROR: $($_.exception.message)" -ForegroundColor Red
        Write-Log -message "ERROR in Add-OU: $($_.exception.message)"
        Read-Host -Prompt "    Enter to continue"        
    }
}

function Add-SecurityGroups {
    <#
    .SYNOPSIS
        Maakt securitygroups aan op basis van een CSV-bestand.
    .DESCRIPTION
        Leest securitygroups.csv met kolommen 'groepnaam' en 'ou' gescheiden door ';'.
        bepaald de scope (domainlocal of Global) op basis van de prefix van de groepen:
            - DL = domainlocal
            - GL = Global
        Groepen met een onbekende prefix worden genegeerd.
        Slaat bestaande groepen over en toont een melding.
        Alle acties worden weggeschreven naar de logfile.
    
    .PARAMETER SettingsPath
        Pad naar het CSV-bestand met groepinfo. Standaard "settings\securitygroups.csv"
    .PARAMETER DomainRoot
        Naam van de Domain. Als er geen domainaam word meegegeven, haalt het script het op van de Server. bv. DomainName.local    
    .EXAMPLE
        Add-SecurityGroups
    .EXAMPLE
        Add-SecurityGroups -SettingsPath "C:\scripts\settings\SecurityGroups.csv"
    #>
    param (
        [string]$SettingsPath = "settings\securitygroups.csv",
        [string]$DomainRoot = (Get-ADDomain).DistinguishedName
    )

    try {
        $Groups = Import-Csv $SettingsPath -Delimiter ';'
        foreach ($Group in $Groups) {
            $GroupName = $Group.GroepNaam.Trim()
            $OUName = $Group.ou.trim()
            $OUPath = "OU=$OUName,$DomainRoot"

            #bepalen tussen domain local en global op basis van prefix (GL en DL) (de scope)
            if ($GroupName -like "DL_*") {
                $Scope = "DomainLocal"
            }
            elseif ($GroupName -like "GL_*") {
                $Scope = "Global"
            }
            else {
                Write-Host "    [!] Unknown prefix for '$GroupName' in XML, skipping." -ForegroundColor Yellow
                write-log -Message "Error in Add-SecurityGroup: unknown prefix for '$GroupName' in XML, skipped."
                continue
            }

            #OU's aanmaken voor de soorten securityroups als die nog niet bestaan
            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OUPath'" -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $OUName -Path $DomainRoot -ProtectedFromAccidentalDeletion $false
                write-host "    OU created: '$OUName'" -ForegroundColor Green
                write-log -Message "Add-SecurityGroups: OU '$OUName' created in '$DomainRoot'."
            }

            #Security groep aanmaken als die nog niet bestaat, indien de user add-securitgroups nog niet heeft uitgevoerd.
            if (-not (Get-ADGroup -filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
                New-ADGroup -Name $GroupName -Path $OUPath -GroupScope $Scope -GroupCategory Security
                Write-Host "`n    Group created: $GroupName ($Scope) in $OUName" -ForegroundColor Green
                Write-Log -message "Sucessfully created securitygroup: $GroupName"
            }
            else {
                Write-Host "`n    [!] Group already exists: $GroupName" -ForegroundColor Yellow
                write-log -Message "Add-SecurityGroups: Group '$GroupName' already exists, skipped."
            }
        }
        Read-Host -Prompt "    Enter to continue"
    }
    catch {
        Write-Host "`n    ERROR: $($_.exception.message)" -ForegroundColor Red
        write-log -Message "ERROR in Add-SecurityGroups: $($_.exception.message)"
        Read-Host -Prompt "    Enter to continue"
    }  
}

function Add-DomainUsers {
    <#
    .SYNOPSIS
        Maakt domain users aan uit JSON bestand en plaatst ze in de juiste OU

    .DESCRIPTION
        leest info uit Users.json en domain.settings.xml
        Voor elke gebruiker, resolve het juiste OU's volle LDAP pad door het op te zoeken in ous.csv,
        Maakt de gebruiker aan met het juiste homefolder en profilefolder pad.
        Als de OU in kwestie nog niet bestaat, maakt hij het aan.
       Alle acties worden wegeschreven naar de logfile.

    .PARAMETER UserPath
        pad to naar users.json file. Default naar 'settings\users.json'.

    .PARAMETER OuPath
        pad naar the ous.csv file. Default naar 'settings\ous.csv'.

    .PARAMETER SettingsPath
        pad naar Domain.Settings.xml. Default naar 'settings\Domain.Settings.xml'.

    .EXAMPLE
        Add-DomainUsers

    .EXAMPLE
        Add-DomainUsers -UserPath 'C:\scripting\settings\users.json' 
    #>
    param (
        [string]$UserPath     = "settings\users.json",
        [string]$OuPath       = "settings\ous.csv",
        [string]$SettingsPath = "settings\Domain.Settings.xml"
    )

    try {
        $Json       = Get-Content -Path $UserPath -ErrorAction Stop
        $Users      = ($Json | ConvertFrom-Json).users
        $OuTable    = Import-Csv $OuPath -Delimiter ';'
        [xml]$Xml   = Get-Content $SettingsPath -ErrorAction Stop
        $DomainRoot = (Get-ADDomain).DistinguishedName

        $UserSettings  = $Xml.Settings.UserSettings
        $FileServer    = $Xml.Settings.FileServer.name
        $DefaultPasswd = $UserSettings.defaultPassword
        $HomeShare     = $UserSettings.homeFolder.sharename
        $HomeDrive     = $UserSettings.homeFolder.homeDrive
        $ProfileShare  = $UserSettings.profileFolder.sharename

        Write-Host "`n    Creating domain users..." -ForegroundColor Green

        foreach ($User in $Users) {
            $FirstName = $User.firstName.Trim()
            $LastName  = $User.lastName.Trim()
            $Login     = $User.login.Trim()
            $OuName    = $User.ou.Trim()

            # Zoek de OU op in ous.csv en bouw het LDAP pad op
            $OuRow = $OuTable | Where-Object { $_.Name.Trim() -eq $OuName }
            if (-not $OuRow) {
                Write-Host "    [!] OU '$OuName' not found in ous.csv, skipping user '$Login'." -ForegroundColor Red
                Write-Log -Message "ERROR in Add-DomainUsers: OU '$OuName' not found in ous.csv, skipped '$Login'."
                continue
            }

            $OuPath = $OuRow.Path.Trim()
            if ($OuPath -ne "") {
                $ParentDN = (($OuPath -split ",") | ForEach-Object { "OU=$_" }) -join ","
                $ParentDN = "$ParentDN,$DomainRoot"
            } else {
                $ParentDN = $DomainRoot
            }

            $OuFullPath = "OU=$OuName,$ParentDN"

            # Maak de OU als die nog niet bestaat
            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OuFullPath'" -ErrorAction SilentlyContinue)) {
                try {
                    New-ADOrganizationalUnit -Name $OuName -Path $ParentDN -ProtectedFromAccidentalDeletion $false
                    Write-Host "    Created missing OU: $OuName" -ForegroundColor Green
                    Write-Log -Message "Add-DomainUsers: created missing OU '$OuName' in '$ParentDN'"
                }
                catch {
                    Write-Host "    [!] Could not create OU '$OuName': $($_.Exception.Message)" -ForegroundColor Red
                    Write-Log -Message "ERROR in Add-DomainUsers: could not create OU '$OuName': $($_.Exception.Message)"
                    continue
                }
            }

            # UNC paden voor home en profile
            $HomeUNC    = "\\$FileServer\$HomeShare\$Login"
            $ProfileUNC = "\\$FileServer\$ProfileShare\$Login"

            # Maak de gebruiker aan
            if (Get-ADUser -Filter "SamAccountName -eq '$Login'" -ErrorAction SilentlyContinue) {
                Write-Host "    [!] User already exists: $Login" -ForegroundColor Yellow
                Write-Log -Message "Add-DomainUsers: user '$Login' already exists, skipped."
                continue
            }

            try {
                New-ADUser `
                    -GivenName             $FirstName `
                    -Surname               $LastName `
                    -Name                  "$FirstName $LastName" `
                    -DisplayName           "$FirstName $LastName" `
                    -SamAccountName        $Login `
                    -Path                  $OuFullPath `
                    -AccountPassword       (ConvertTo-SecureString $DefaultPasswd -AsPlainText -Force) `
                    -HomeDirectory         $HomeUNC `
                    -HomeDrive             "$($HomeDrive):" `
                    -ProfilePath           $ProfileUNC `
                    -Enabled               $true `
                    -ChangePasswordAtLogon $true

                Write-Host "    Created user: $Login in OU '$OuName'" -ForegroundColor Green
                Write-Log -Message "Add-DomainUsers: created user '$Login' ($FirstName $LastName) in OU '$OuName'"
            }
            catch {
                Write-Host "    [!] Failed to create user '$Login': $($_.Exception.Message)" -ForegroundColor Red
                Write-Log -Message "ERROR in Add-DomainUsers: failed to create '$Login': $($_.Exception.Message)"
            }
        }

        Read-Host -Prompt "`n    Enter to continue"
    }
    catch {
        Write-Host "    ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Message "ERROR in Add-DomainUsers: $($_.Exception.Message)"
        Read-Host -Prompt "    Enter to continue"
    }
}

Function Add-UsersToSecurityGroups {
    <#
    .SYNOPSIS
        Voegt domain users toe aan securitygroups op basis van de inhoud van users.json.
    .DESCRIPTION
        Leest users.json uit en loopt over alle gebruikers en hun 'securitygroups' veld.
        Per gebruiker wordt elke opgegeven groep opgezocht in AD.
        bestaat de groep: De gebruiker wordt toegevoegd.
        Bestaat de groep niet: er verschijnt een melding en de groep word overgeslagen.
        Alle acties weggeschreven naar logfile.
    
    .PARAMETER UserPath
        Pad naar het JSON-bestand met gebruikersinformatie. Standaard: 'Settings\users.json'
    
    .EXAMPLE
        Add-UsersToSecurityGroups
    .EXAMPLE
        Add-UsersToSecurityGroups -UserPath "C:\scripts\settings\users.json"
    #>
    param (
        [string]$UserPath = 'settings\users.json'
    )

    try {
        $Json = get-Content -path $UserPath -ErrorAction stop
        $Users = ($Json | convertfrom-json).users

        foreach ($User in $Users) {
            $Login = $User.login.trim()

            foreach ($Group in $User.securitygroups) {
                $GroupName = $Group.Trim()

                if (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue) {
                    try{
                        Add-ADGroupMember -Identity $GroupName -Members $Login -ErrorAction SilentlyContinue
                        Write-Host "    Added $Login to group: $GroupName" -ForegroundColor Green
                        Write-Log -message "Added user: $Login to securitygroup: $GroupName" 
                    }
                    Catch {
                        Write-Host "    [!] Failed to add user: $login to securitygroup: $GroupName"
                        write-log -Message "Failed to add user: $login to securitygroup: $GroupName"
                    }
                }
                else {
                    Write-Host "    [!] Group not found: $GroupName" -ForegroundColor Red
                    Write-Log -message "ERROR: group '$GroupName' not found, skipped for '$Login'." 
                    }
                }
            }
        Read-Host -Prompt "`n   Enter to continue"
    }
    catch {
        Write-Host "    ERROR: $($_.exception.message)" -ForegroundColor Red
        Write-Log -message "ERROR in Add-UsersToSecurityGroups: $($_.exception.message)"
        Read-Host -Prompt "`n   Enter to continue"
    }
}

function Join-Domain {
    <#
    .SYNOPSIS
        Voegt computer toe aan een active directory domein.
    
    .DESCRIPTION
        Leest de domeinnaam uit Domain.Settings.xml. Controleert eerst of de computer al lid is van het domein, en slaat de actie over als dat het geval is.
        Vraagt om domeinadmin-credentials via get-credential pop up, voert daarna Add-computer uit en herstart de computer automatisch.
        Alle acties worden weggeschreven naar de logfile.
    
    .PARAMETER DomainXml
        Pad naar xml config bestand. Standaard: "settings\Domain.Settings.xml"
    
    .EXAMPLE
        Join-Domain
    .EXAMPLE
        Join-Domain -Domainxml "C:\scripts\settings\Domain.Settings.xml"
    #>
    param (
        $DomainXml = "settings\Domain.Settings.xml"
    )

    try {
        [xml]$Settings = Get-Content $DomainXml -ErrorAction Stop
        $DomainName = $Settings.Settings.Domain.domainname
        $CurrentComputerName = $env:COMPUTERNAME
        $CurrentDomain = (Get-WmiObject Win32_ComputerSystem).Domain
        if ($CurrentDomain -eq $DomainName) {
            Write-Host "    [!] $CurrentComputerName is already in the domain: $DomainName" -ForegroundColor Yellow
            Write-Log -Message "Join-Domain: Already part of $DomainName, skipped join."
            Read-Host -Prompt "`n   Enter to continue"
        }

        $Credential = Get-Credential -Message "Enter the domain admin credentials for '$DomainName'"

        Add-Computer -DomainName $DomainName -Credential $Credential -Force
        write-host "    Attempting to join $CurrentComputerName to domain: $DomainName..." -ForegroundColor Green
        Write-Log -message "Join-Domain: Joined domain '$DomainName'"
        Write-Host "    [!] Rebooting..." -ForegroundColor Yellow
        Read-Host -Prompt "`n     Enter to continue"    
        Restart-Computer -Force
    }
    catch [System.IO.FileNotFoundException]{
        Write-Host "    [!] ERROR: Domain.Settings.xml not found" -ForegroundColor Red
        Write-Log -message "ERROR in Join-Domain: $($_.exception.message)"
        Read-Host -Prompt "`n     Enter to continue"
    }
    catch {
        Write-Host "    [!] ERROR: $($_.exception.message)" -ForegroundColor Red
        Write-Log -message "ERROR in Join-Domain: $($_.exception.message)"
        Read-Host -Prompt "`n     Enter to continue"
    } 
}


Export-ModuleMember -Function *