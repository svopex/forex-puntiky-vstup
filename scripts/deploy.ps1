# Nasazeni experta Puntiky Quick Entry do MetaTraderu 5.
#
# Skript zkopiruje zdrojovy soubor z repozitare do datoveho adresare
# terminalu a nasledne ho zkompiluje pres MetaEditor. Po uspesne kompilaci
# staci v terminalu v Navigatoru (Experts -> Puntiky -> PuntikyQuickEntry) experta
# pretahnout na graf XAUUSD - pri bezicim terminalu se novy .ex5 objevi
# v Navigatoru sam, pripadne po pravem kliku -> Obnovit.
#
# Pouziti:
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Broker "IC Markets"
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -NoCompile

param(
    # Cast nazvu instalacniho adresare terminalu (rozlisuje brokera)
    [string]$Broker = "RoboForex",
    # Preskocit kompilaci a jen zkopirovat soubory
    [switch]$NoCompile
)

$ErrorActionPreference = "Stop"

# Nazev souboru experta (.mq5 / .ex5) a slozky, do ktere se nasazuje -
# slozka je kratsi "Puntiky", expert je v Navigatoru pod Experts -> Puntiky
$expertName = "PuntikyQuickEntry"
$expertDir  = "Puntiky"
$repoRoot   = Split-Path -Parent $PSScriptRoot
$srcExperts = Join-Path $repoRoot "MQL5\Experts\$expertDir"

# Najde instalacni adresar terminalu podle nazvu brokera
$install = Get-ChildItem "C:\Program Files" -Directory |
           Where-Object { $_.Name -like "*$Broker*" } |
           Select-Object -First 1
if ($null -eq $install) {
    throw "Instalace terminalu pro brokera '$Broker' nebyla nalezena v C:\Program Files."
}
$installPath = $install.FullName

# Datovy adresar terminalu se pozna podle souboru origin.txt, ktery
# obsahuje cestu k instalaci (soubor je v UTF-16 s BOM)
$termRoot = $null
foreach ($dir in Get-ChildItem "$env:APPDATA\MetaQuotes\Terminal" -Directory) {
    $originFile = Join-Path $dir.FullName "origin.txt"
    if (-not (Test-Path $originFile)) { continue }
    $origin = (Get-Content $originFile -Raw -Encoding Unicode).Trim([char]0xFEFF, ' ', "`r", "`n", "`0")
    if ($origin -eq $installPath) { $termRoot = $dir.FullName; break }
}
if ($null -eq $termRoot) {
    throw "Datovy adresar terminalu pro '$installPath' nebyl nalezen (terminal jeste nebyl spusten?)."
}

Write-Output "Terminal:  $installPath"
Write-Output "Data:      $termRoot"

# Kopie zdrojovych souboru do datoveho adresare terminalu
$dstExperts = Join-Path $termRoot "MQL5\Experts\$expertDir"
New-Item -ItemType Directory -Force -Path $dstExperts | Out-Null
Copy-Item (Join-Path $srcExperts "*.mq5") $dstExperts -Force
Write-Output "Zkopirovano do $dstExperts"

if ($NoCompile) { return }

# Kompilace pres MetaEditor - vysledek se cte z logu (log je v UTF-16)
$editor = Join-Path $installPath "MetaEditor64.exe"
if (-not (Test-Path $editor)) { throw "MetaEditor64.exe nenalezen v $installPath" }

$source = Join-Path $dstExperts "$expertName.mq5"
$log    = Join-Path $env:TEMP "$expertName`_compile.log"
if (Test-Path $log) { Remove-Item $log -Force }

Start-Process -FilePath $editor `
              -ArgumentList "/compile:`"$source`"", "/log:`"$log`"" `
              -Wait -NoNewWindow

# Z logu se vypisou jen chyby, varovani a souhrnny radek
if (Test-Path $log) {
    Get-Content $log -Encoding Unicode |
        Where-Object { $_ -match "error|warning|Result" } |
        ForEach-Object { Write-Output $_ }
} else {
    Write-Output "Log kompilace nebyl vytvoren."
}

$ex5 = Join-Path $dstExperts "$expertName.ex5"
if (Test-Path $ex5) {
    Write-Output "Hotovo: $ex5"
} else {
    throw "Kompilace selhala - .ex5 nebyl vytvoren."
}

# Uklid: drivejsi verze se nasazovaly do slozky pojmenovane podle experta
# (MQL5\Experts\PuntikyQuickEntry). Stara kopie by v Navigatoru zustala jako
# druhy expert, proto se smaze. Kdyz ji bezici terminal drzi, jen se upozorni.
$oldExperts = Join-Path $termRoot "MQL5\Experts\$expertName"
$oldRemoved = $false
if (($oldExperts -ne $dstExperts) -and (Test-Path $oldExperts)) {
    try {
        Remove-Item $oldExperts -Recurse -Force -ErrorAction Stop
        Write-Output "Smazana stara slozka $oldExperts"
        $oldRemoved = $true
    } catch {
        Write-Output "POZOR: starou slozku $oldExperts se nepodarilo smazat ($($_.Exception.Message)) - smaz ji rucne."
    }
}

# Bezici terminal experta po kompilaci obvykle sam znovu nacte, ale ne vzdy
# (napr. kdyz expert zrovna obchoduje) - v grafu pak dal bezi stara verze.
# Kontrola: v Expert logu se ma objevit radek "PQE: rychly vstup spusten ...
# build <cas kompilace>", stejny cas je i v bubline titulku panelu.
$running = Get-Process -Name "terminal64" -ErrorAction SilentlyContinue |
           Where-Object { $_.Path -like "$installPath*" }
if ($null -ne $running) {
    Write-Output ""
    if ($oldRemoved) {
        # Expert v grafu je navazany na cestu ke staremu .ex5 - z nove slozky se sam nenacte
        Write-Output "POZOR: terminal bezi a expert se presunul do nove slozky. Expert v grafu se sam neprenacte -"
        Write-Output "       odeber ho ze VSECH grafu a pridej znovu z Navigatoru (Experts -> $expertDir -> $expertName)."
    } else {
        Write-Output "POZOR: terminal bezi. Pokud se v Expert logu neobjevi 'PQE: ... build $(Get-Date -Format 'yyyy.MM.dd HH:mm')',"
        Write-Output "       odeber experta ze VSECH grafu a pridej ho znovu (nebo restartuj terminal)."
    }
}
