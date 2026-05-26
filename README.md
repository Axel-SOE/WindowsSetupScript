# Windows Setup Automation – Scripting Project ASo

**Auteur:** Axel Soebert – 1SNB_D2A  
**Opleiding:** Graduaat Systeem- en Netwerkbeheer – AP Hogeschool Antwerpen

---

## Overzicht

Dit project is een modulair PowerShell-toolkit voor de geautomatiseerde configuratie van Windows Server omgevingen en Windows-clients. Via een menu-gestuurd hoofdscript kunnen een domeincontroller, Active Directory-structuur, gebruikers, netwerkinstellingen, mappen, shares en NTFS-rechten volledig automatisch worden opgezet op basis van externe configuratiebestanden.

---

## Projectstructuur

```
scripting/
├── MenuASo.ps1                  # Hoofdscript – startpunt van de toolkit
├── modules/
│   ├── algemeenASo.psm1         # Algemene functies (netwerk, mappen, shares, logging, ...)
│   └── domainsettingsASo.psm1   # Domein- en Active Directory functies
├── settings/
│   ├── Computer.Settings.xml    # Computernaam en netwerkinstellingen per adapter
│   ├── Domain.Settings.xml      # Domeinnaam, gebruikersinstellingen, home/profielmappen
│   ├── mappen.txt               # Lijst van aan te maken mappen
│   ├── ous.csv                  # Organisatie-eenheden (OU's) met padstructuur
│   ├── securitygroups.csv       # Beveiligingsgroepen
│   ├── shares.csv               # Gedeelde mappen (shares) met toewijzing aan map
│   ├── rechten.csv              # NTFS-rechten per map/groep
│   └── users.json               # Gebruikersaccounts met groep- en OU-toewijzing
└── logs/
    └── InstallatieLogASo.txt    # Automatisch gegenereerd installatielogboek
```

---

## Vereisten

- Windows Server 2019 / 2022 (of Windows 10/11 voor clientconfiguratie)
- PowerShell 5.1 of hoger
- **Uitvoeren als Administrator** (verplicht – het script controleert dit automatisch)
- De juiste MAC-adressen ingevuld in `Computer.Settings.xml` voor netwerkconfiguratie

---

## Gebruik

1. Open PowerShell **als Administrator**
2. Navigeer naar de map van het project
3. Voer het hoofdscript uit:

```powershell
.\MenuASo.ps1
```

Het script detecteert automatisch of het op een Windows Server of een Windows-client draait, en past het menu hierop aan.

---

## Hoofdmenu

Het hoofdmenu biedt drie opties:

| Keuze | Beschrijving |
|-------|-------------|
| `1` | Basisapparaat configuratie |
| `2` | Server- en domeinconfiguratie |
| `3` | Windows-clientconfiguratie *(niet beschikbaar op Server)* |
| `Q` | Afsluiten |

---

## Modules

### `algemeenASo.psm1` – Algemene functies

| Functie | Beschrijving |
|---------|-------------|
| `Show-Menu` | Toont een genummerd keuzemenu in de console |
| `Invoke-BasicConfigMenu` | Menu voor basisinstellingen (computernaam, netwerk, ...) |
| `Invoke-ClientConfigMenu` | Menu voor Windows-clientspecifieke instellingen |
| `Set-NetAdapterProperties` | Configureert netwerkadapters op basis van MAC-adres uit XML |
| `Enter-AutoLogin` | Stelt automatisch inloggen in via het register |
| `Enter-RunOnce` | Registreert een script voor éénmalige uitvoering bij opstart |
| `Clear-AutoLogin` | Verwijdert de autologon-registervermeldingen |
| `Add-Directory` | Maakt mappen aan op basis van `mappen.txt` |
| `Add-Shares` | Maakt SMB-shares aan op basis van `shares.csv` |
| `Add-Permissions` | Stelt NTFS-rechten in op basis van `rechten.csv` |
| `Write-Log` | Schrijft berichten naar het installatielogboek |

### `domainsettingsASo.psm1` – Domein- en AD-functies

| Functie | Beschrijving |
|---------|-------------|
| `Invoke-DomainConfigMenu` | Menu voor alle domeingerelateerde acties |
| `Install-DomainController` | Promoveert de server naar domeincontroller (AD DS) |
| `Add-OU` | Maakt organisatie-eenheden aan op basis van `ous.csv` |
| `Add-SecurityGroups` | Maakt beveiligingsgroepen aan op basis van `securitygroups.csv` |
| `Add-DomainUsers` | Maakt domeingebruikers aan op basis van `users.json` |
| `Join-Domain` | Voegt een computer toe aan het domein |

---

## Configuratiebestanden

### `Computer.Settings.xml`
Definieert de computernaam en de netwerkinstellingen per adapter. Adapters worden gekoppeld via hun MAC-adres, waardoor de configuratie hardwareoverstijgend werkt.

```xml
<networkadapter>
    <name>lan1</name>
    <macaddress>00-0C-29-42-D9-C9</macaddress>
    <dhcpenabled>false</dhcpenabled>
    <ip>10.1.10.201</ip>
    ...
</networkadapter>
```

### `Domain.Settings.xml`
Bevat de domeinnaam, NetBIOS-naam, en instellingen voor gebruikers-home- en profielmappen.

### `ous.csv`
Lijst van OU's met hun pad in de AD-structuur. Gescheiden door `;`.

### `securitygroups.csv` / `users.json`
Definities van beveiligingsgroepen en gebruikersaccounts met OU- en groepstoewijzingen.

### `shares.csv` / `rechten.csv`
Koppelen mappen aan sharenames en stellen NTFS-rechten in per groep.

---

## Logging

Alle acties worden automatisch bijgehouden in `logs/InstallatieLogASo.txt`. Elk logbericht bevat een tijdstempel en een omschrijving van de uitgevoerde actie of een eventuele fout.

---

## Opmerkingen

- Het script vereist een herstart na bepaalde stappen (bijv. na DC-promotie). Autologon en RunOnce worden gebruikt om het script na herstart automatisch verder te laten lopen.
- De OS-detectie maakt gebruik van de registersleutel `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` in plaats van `Get-ComputerInfo` voor snellere opstarttijd.
- Alle functies maken gebruik van `param()`-blokken en bevatten comment-based help (`Get-Help <functienaam>` werkt).
