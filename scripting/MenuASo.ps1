#Axel Soebert - 1SNB_D2A - MenuASo.ps1
Set-Location $PSScriptRoot
#Requires -RunAsAdministrator
Set-TimeZone -Name "Romance Standard Time" -ErrorAction SilentlyContinue

Remove-Module -name algemeenASo, domainsettingsASo -ErrorAction SilentlyContinue
Import-Module .\modules\algemeenASo.psm1, .\modules\domainsettingsASo.psm1 

#Ik heb voor te checken of het een server was opgezocht hoe ik dit beter kon doen. Ik gebruikte eerst (get-computerinfo).osname voor het detecteren of het een server is, maar dan was er vaak even een korte wachtijd bij het starten omdat het script ineens veel data moest ophalen in de plaats van een enkele value.
#Bron: Claude.ai
$OSVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
$IsServer = $OSVersion -match "Server"

do {
    Clear-AutoLogin
    $ChoiceMenu = Show-Menu -Title "Welcome to Axel's Windows setup PowerShell script!" -MenuOptions @(
    "1: Basic device Config",      
    "2: Server/domain config",
    "3: Windows client config"   
    )
    switch ($ChoiceMenu) {
        '1' { Invoke-BasicConfigMenu }
        '2' { Invoke-DomainConfigMenu }
        '3' {
            if ($IsServer) {
                Write-Host " [!]  Windows client config is not available on Windows Server." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
            else {
                Invoke-ClientConfigMenu
            }
        }
        'Q' {}
        Default { Write-Host "`n    Invalid choice." -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
    }

} while (($ChoiceMenu).ToUpper() -ne 'Q')