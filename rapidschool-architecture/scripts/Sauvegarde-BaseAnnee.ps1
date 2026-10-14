<#
.SYNOPSIS
    Sauvegarde vérifiée d'une base d'année RapidSchool (pg_dump), avec rotation.

.DESCRIPTION
    1. pg_dump au format personnalisé (-Fc : compressé, restauration sélective possible)
       dans un fichier temporaire ;
    2. vérification : l'archive est relue par pg_restore --list et doit contenir
       les données de chaque table attendue ; sinon le fichier est supprimé et
       le script sort en erreur (code 1) ;
    3. le fichier n'est renommé en .dump qu'une fois vérifié : une sauvegarde
       interrompue ne peut jamais être prise pour une sauvegarde valide ;
    4. empreinte SHA-256 à côté du fichier (contrôle d'intégrité après copie) ;
    5. suppression des sauvegardes plus anciennes que -Conserver jours,
       en gardant toujours au moins les 3 plus récentes.

    Prévu pour le Planificateur de tâches Windows (code de sortie 0 / 1, journal).
    Le mot de passe n'est jamais dans le script : il est lu par pg_dump dans
    %APPDATA%\postgresql\pgpass.conf (ou la variable PGPASSFILE).
    Compatible Windows PowerShell 5.1 et PowerShell 7.

.EXAMPLE
    .\Sauvegarde-BaseAnnee.ps1 -Base bd_ecolg2025_2026 -Dossier D:\Sauvegardes\RapidSchool

.EXAMPLE
    # Restauration dans une base vide (test de restauration périodique recommandé) :
    # createdb -U postgres bd_test_restauration
    # pg_restore -U postgres -d bd_test_restauration --no-owner --exit-on-error fichier.dump
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_]+$')][string]$Base,
    [Parameter(Mandatory = $true)][string]$Dossier,
    [string]$Hote = 'localhost',
    [int]$Port = 5432,
    [string]$Utilisateur = 'rs_sauvegarde',
    [int]$Conserver = 30,
    [string]$PgBin = '',
    [string[]]$TablesAttendues = @('eleve', 'transition', 'note', 'absence')
)

$ErrorActionPreference = 'Stop'
# accepte aussi "eleve,note" passé en une seule chaîne (powershell -File, Planificateur de tâches)
$TablesAttendues = @($TablesAttendues -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$journal = Join-Path $Dossier 'sauvegarde.log'

function Write-Journal([string]$niveau, [string]$message) {
    $ligne = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2} : {3}' -f (Get-Date), $niveau, $Base, $message
    Add-Content -Path $journal -Value $ligne -Encoding UTF8
    Write-Output $ligne
}

function Find-OutilPostgres([string]$nom) {
    $exe = if ($IsLinux -or $IsMacOS) { $nom } else { "$nom.exe" }
    if ($PgBin) { return (Join-Path $PgBin $exe) }
    $cmd = Get-Command $exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # Installation standard : prendre la version de PostgreSQL la plus récente
    $candidat = Get-ChildItem "$env:ProgramFiles\PostgreSQL\*\bin\$exe" -ErrorAction SilentlyContinue |
        Sort-Object { [int]($_.Directory.Parent.Name -replace '\D.*$', '') } -Descending |
        Select-Object -First 1
    if ($candidat) { return $candidat.FullName }
    throw "$exe introuvable : indiquer le dossier avec -PgBin"
}

New-Item -ItemType Directory -Path $Dossier -Force | Out-Null
$horodatage = Get-Date -Format 'yyyyMMdd_HHmmss'
$final      = Join-Path $Dossier "$Base`_$horodatage.dump"
$temporaire = "$final.partiel"

try {
    $pgDump    = Find-OutilPostgres 'pg_dump'
    $pgRestore = Find-OutilPostgres 'pg_restore'

    # 1. Sauvegarde
    $debut = Get-Date
    & $pgDump --host=$Hote --port=$Port --username=$Utilisateur --no-password `
              --format=custom --compress=6 --file=$temporaire $Base
    if ($LASTEXITCODE -ne 0) { throw "pg_dump a échoué (code $LASTEXITCODE)" }

    # 2. Vérification : archive lisible et données présentes pour chaque table attendue
    $contenu = & $pgRestore --list $temporaire
    if ($LASTEXITCODE -ne 0) { throw "archive illisible par pg_restore (code $LASTEXITCODE)" }
    $donnees = $contenu | Where-Object { $_ -match ' TABLE DATA public (\S+) ' } |
               ForEach-Object { $Matches[1] }
    $manquantes = $TablesAttendues | Where-Object { $donnees -notcontains $_ }
    if ($manquantes) { throw "données absentes de l'archive pour : $($manquantes -join ', ')" }

    # 3. Validation du fichier, 4. empreinte
    Move-Item -Path $temporaire -Destination $final
    $hash = (Get-FileHash -Path $final -Algorithm SHA256).Hash
    Set-Content -Path "$final.sha256" -Value "$hash  $(Split-Path $final -Leaf)" -Encoding ASCII

    $taille = '{0:N1} Mo' -f ((Get-Item $final).Length / 1MB)
    $duree  = '{0:N0} s' -f ((Get-Date) - $debut).TotalSeconds
    Write-Journal 'OK' "$(Split-Path $final -Leaf), $taille, $($donnees.Count) tables, $duree"

    # 5. Rotation (jamais moins de 3 sauvegardes conservées)
    $anciennes = Get-ChildItem -Path $Dossier -Filter "$Base`_*.dump" |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -Skip 3 |
                 Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Conserver) }
    foreach ($f in $anciennes) {
        Remove-Item -Path $f.FullName, "$($f.FullName).sha256" -Force -ErrorAction SilentlyContinue
        Write-Journal 'INFO' "supprimée (plus de $Conserver jours) : $($f.Name)"
    }
    exit 0
}
catch {
    if (Test-Path $temporaire) { Remove-Item $temporaire -Force }
    Write-Journal 'ERREUR' $_.Exception.Message
    exit 1
}
