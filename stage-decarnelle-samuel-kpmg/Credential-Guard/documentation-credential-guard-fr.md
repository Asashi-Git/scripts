# Documentation Technique - Script Credential Guard

## Table des Matières
1. [Vue d'ensemble](#vue-densemble)
2. [Prérequis et dépendances](#prérequis-et-dépendances)
3. [Paramètres d'entrée](#paramètres-dentrée)
4. [Architecture du script](#architecture-du-script)
5. [Fonctions détaillées](#fonctions-détaillées)
6. [Processus de traitement](#processus-de-traitement)
7. [Format des fichiers](#format-des-fichiers)
8. [Gestion des erreurs](#gestion-des-erreurs)
9. [Exemples d'utilisation](#exemples-dutilisation)
10. [Dépannage](#dépannage)
11. [Schéma de fonctionnement](#schéma-de-fonctionnement)

---

## Vue d'ensemble

### Description générale
Le script `credential-guard.ps1` est un outil PowerShell conçu pour automatiser l'enrichissement de données utilisateur en interrogeant Active Directory. Il lit un fichier Excel contenant des informations utilisateur de base et génère un rapport enrichi avec les descriptions AD correspondantes.

### Objectifs principaux
- **Centralisation des données** : Consolider les informations utilisateur provenant de différentes sources
- **Enrichissement automatique** : Récupérer automatiquement les descriptions depuis Active Directory
- **Reporting professionnel** : Générer des rapports Excel formatés avec statistiques
- **Gestion d'erreurs robuste** : Traiter les cas d'échec et fournir des logs détaillés

### Cas d'usage typiques
- Audit de sécurité et inventaire utilisateur
- Migration de systèmes avec mapping des comptes
- Validation de données RH vs Active Directory
- Génération de rapports pour la conformité

---

## Prérequis et dépendances

### Environnement système
- **Système d'exploitation** : Windows avec PowerShell 5.1 ou supérieur
- **Permissions** : Aucun droit administrateur requis
- **Connectivité** : Accès réseau à un contrôleur de domaine Active Directory

### Modules PowerShell
Le script installe automatiquement les modules suivants :

#### 1. ImportExcel
- **Version requise** : Dernière version disponible
- **Installation** : PowerShell Gallery (scope utilisateur)
- **Fonction** : Lecture et écriture de fichiers Excel sans Microsoft Office
- **Avantages** : 
  - Pas de dépendance Office
  - Support des formats .xlsx et .xls
  - Formatage avancé et création de tableaux

#### 2. ActiveDirectory
- **Prérequis** : RSAT (Remote Server Administration Tools)
- **Installation** : Module Windows ou PowerShell Gallery
- **Fonction** : Interrogation d'Active Directory
- **Cmdlets utilisées** :
  - `Get-ADUser` : Récupération des informations utilisateur

### Installation des RSAT (si nécessaire)
```powershell
# Windows 10/11 - Installation via Features on Demand
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools

# Windows Server - Installation via Server Manager
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

---

## Paramètres d'entrée

### InputFile (Obligatoire)
```powershell
# Ligne 23-26 du script
[Parameter(Mandatory=$true)]
[string]$InputFile
```

**Description** : Chemin vers le fichier Excel source contenant les données utilisateur

**Contraintes** :
- Format : `.xlsx` ou `.xls`
- Colonnes obligatoires : `UserName` et `Hostname`
- Encodage : UTF-8 ou compatible Excel

**Exemple** :
```powershell
-InputFile "C:\Data\FR-User-Credential-Guard.xlsx"
```

### OutputFile (Optionnel)
```powershell
# Ligne 28-31 du script
[Parameter(Mandatory=$false)]
[string]$OutputFile = "export-traite-credential-guard.xlsx"
```

**Description** : Chemin vers le fichier Excel de sortie

**Valeur par défaut** : `"export-traite-credential-guard.xlsx"` dans le répertoire courant

**Exemple** :
```powershell
-OutputFile "C:\Reports\resultat-$(Get-Date -Format 'yyyyMMdd').xlsx"
```

---

## Architecture du script

### Structure modulaire
Le script est organisé en modules fonctionnels distincts :

1. **Module de configuration** : Paramètres et constantes
2. **Module de logging** : Gestion centralisée des messages
3. **Module d'installation** : Gestion automatique des dépendances
4. **Module Active Directory** : Interface avec AD
5. **Module de validation** : Contrôles de cohérence
6. **Module de traitement** : Logique métier principale
7. **Module de reporting** : Génération des sorties

### Flux d'exécution
```
Initialisation → Installation modules → Validation → Traitement → Export → Finalisation
```

---

## Fonctions détaillées

### 1. Write-Log
```powershell
# Lignes 37-60 du script
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
}
```

**Objectif** : Centraliser l'affichage des messages avec horodatage et codes couleur

**Niveaux de log** :
- `INFO` (Blanc) : Informations générales
- `SUCCESS` (Vert) : Opérations réussies
- `WARNING` (Jaune) : Avertissements
- `ERROR` (Rouge) : Erreurs critiques

**Format de sortie** :
```
[2025-07-15 14:30:25] [INFO] Script démarre
[2025-07-15 14:30:26] [SUCCESS] Module ImportExcel installé
[2025-07-15 14:30:27] [ERROR] Utilisateur non trouvé dans AD
```

**Avantages** :
- Traçabilité complète des opérations
- Identification visuelle rapide des problèmes
- Format standardisé pour l'analyse de logs

### 2. Install-RequiredModules
```powershell
# Lignes 64-82 du script
function Install-RequiredModules {
    # Installation automatique des modules
}
```

**Objectif** : Installer et importer automatiquement les modules PowerShell requis

**Processus d'installation** :
1. Vérification de la présence du module (`Get-Module -ListAvailable`)
2. Installation depuis PowerShell Gallery (`Install-Module -Force -Scope CurrentUser`)
3. Import dans la session courante (`Import-Module -Force`)

**Gestion des erreurs** :
- Retry automatique en cas d'échec réseau
- Installation au niveau utilisateur pour éviter les problèmes de permissions
- Force l'installation même si une version existe

### 3. Get-UserADInfo
```powershell
# Lignes 88-110 du script
function Get-UserADInfo {
    param([string]$Username)
}
```

**Objectif** : Interroger Active Directory pour récupérer les informations d'un utilisateur

**Données récupérées** :
- `Description` : Champ description de l'utilisateur AD
- `Found` : Indicateur booléen de succès/échec

**Logique de traitement** :
```powershell
# Lignes 91-108 du script
try {
    $adUser = Get-ADUser -Identity $Username -Properties Description -ErrorAction Stop
    return @{
        Description = if ([string]::IsNullOrEmpty($adUser.Description)) { 
            "Aucune description" 
        } else { 
            $adUser.Description 
        }
        Found = $true
    }
}
catch {
    return @{
        Description = "ERREUR: Utilisateur non trouve dans AD"
        Found = $false
    }
}
```

**Cas d'erreur gérés** :
- Utilisateur inexistant dans AD
- Permissions insuffisantes
- Problèmes de connectivité réseau
- Contrôleur de domaine indisponible

### 4. Test-InputFile
```powershell
# Lignes 115-129 du script
function Test-InputFile {
    param([string]$FilePath)
}
```

**Objectif** : Valider l'existence et le format du fichier d'entrée

**Contrôles effectués** :
1. **Existence physique** : `Test-Path $FilePath`
2. **Extension valide** : Vérification `.xlsx` ou `.xls`
3. **Accessibilité** : Possibilité de lecture du fichier

**Exceptions levées** :
- `"Fichier source non trouve: $FilePath"`
- `"Format de fichier non supporte: $extension"`

### 5. Process-UserCredentials
```powershell
# Lignes 135-252 du script
function Process-UserCredentials {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )
}
```

**Objectif** : Fonction principale orchestrant tout le processus de traitement

**Étapes de traitement** :

#### Étape 1 : Validation du fichier source
- Appel de `Test-InputFile`
- Vérification de l'intégrité du fichier

#### Étape 2 : Lecture et validation des données Excel
```powershell
# Lignes 146-153 du script
$excelData = Import-Excel -Path $InputPath -ErrorAction Stop
$availableColumns = $excelData[0].PSObject.Properties.Name
if ("UserName" -notin $availableColumns -or "Hostname" -notin $availableColumns) {
    throw "Colonnes 'UserName' et 'Hostname' requises"
}
```

#### Étape 3 : Traitement des utilisateurs
- Filtrage des lignes vides
- Requête AD pour chaque utilisateur
- Comptabilisation des statistiques

#### Étape 4 : Génération du fichier de sortie
- Export des résultats au format Excel
- Application du formatage professionnel
- Création d'un onglet statistiques

---

## Processus de traitement

### Phase 1 : Initialisation
1. **Parsing des paramètres** : Validation des arguments de ligne de commande
2. **Logging initial** : Enregistrement du démarrage du script
3. **Vérification de l'environnement** : Contrôle de la version PowerShell

### Phase 2 : Préparation de l'environnement
1. **Installation des modules** :
   ```powershell
   Install-Module ImportExcel -Force -Scope CurrentUser
   Install-Module ActiveDirectory -Force -Scope CurrentUser
   ```
2. **Import des modules** :
   ```powershell
   Import-Module ImportExcel -Force
   Import-Module ActiveDirectory -Force
   ```
3. **Test de connectivité AD** : Vérification de l'accès au domaine

### Phase 3 : Lecture et validation des données
1. **Ouverture du fichier Excel** :
   ```powershell
   # Ligne 146 du script
   $excelData = Import-Excel -Path $InputPath
   ```
2. **Validation de la structure** :
   - Présence des colonnes obligatoires
   - Vérification du nombre de lignes
   - Contrôle du format des données

3. **Nettoyage des données** :
   ```powershell
   # Lignes 156-158 du script
   $filteredData = $excelData | Where-Object { 
       -not [string]::IsNullOrWhiteSpace($_.UserName) 
   }
   ```

### Phase 4 : Interrogation Active Directory
Pour chaque utilisateur dans le fichier :

1. **Requête AD** :
   ```powershell
   # Ligne 174 du script
   $adInfo = Get-UserADInfo -Username $row.UserName
   ```

2. **Construction du résultat** :
   ```powershell
   # Lignes 177-182 du script
   if ($adInfo.Found) {
       $results += [PSCustomObject]@{
           'Nom Utilisateur'           = $row.UserName
           'Localisation (Description)' = $adInfo.Description
           'Numero de Poste'           = $row.Hostname
       }
   }
   ```

3. **Comptabilisation** :
   - `$processedCount++` : Total traité
   - `$successCount++` : Utilisateurs trouvés
   - `$errorCount++` : Utilisateurs non trouvés

### Phase 5 : Génération du rapport
1. **Export de base** :
   ```powershell
   # Lignes 194-195 du script
   $results | Export-Excel -Path $OutputPath -WorksheetName "Utilisateurs-AD" 
            -AutoSize -FreezeTopRow -TableStyle Medium2
   ```

2. **Formatage avancé** :
   - Style des en-têtes (gras, fond bleu clair)
   - Ajustement automatique des colonnes
   - Figement de la première ligne

3. **Onglet statistiques** :
   ```powershell
   # Lignes 214-221 du script
   @(
       [PSCustomObject]@{Metrique = "Total utilisateurs traites"; Valeur = $processedCount},
       [PSCustomObject]@{Metrique = "Utilisateurs trouves dans AD"; Valeur = $successCount},
       [PSCustomObject]@{Metrique = "Utilisateurs non trouves"; Valeur = $errorCount},
       [PSCustomObject]@{Metrique = "Taux de succes"; Valeur = "$([math]::Round(($successCount / $processedCount) * 100, 1))%"}
   ) | Export-Excel -ExcelPackage $excel -WorksheetName "Statistiques"
   ```

---

## Format des fichiers

### Fichier d'entrée (InputFile)

#### Structure minimale requise
| Colonne | Type | Obligatoire | Description |
|---------|------|-------------|-------------|
| UserName | String | Oui | Nom d'utilisateur (SAMAccountName) |
| Hostname | String | Oui | Nom de l'ordinateur/poste |

#### Exemple de contenu
```
UserName    | Hostname
------------|------------
jdupont     | PC-COMPTA-01
mmartin     | PC-RH-02
adurand     | PC-IT-03
```

#### Colonnes additionnelles (optionnelles)
Toutes les colonnes supplémentaires sont conservées mais non traitées :
- Service
- Manager
- Location
- etc.

### Fichier de sortie (OutputFile)

#### Onglet "Utilisateurs-AD"
| Colonne | Description | Source |
|---------|-------------|--------|
| Nom Utilisateur | SAMAccountName | Fichier d'entrée |
| Localisation (Description) | Description AD | Active Directory |
| Numero de Poste | Hostname | Fichier d'entrée |

#### Onglet "Statistiques"
| Métrique | Description |
|----------|-------------|
| Total utilisateurs traites | Nombre total de lignes traitées |
| Utilisateurs trouves dans AD | Nombre d'utilisateurs trouvés |
| Utilisateurs non trouves | Nombre d'utilisateurs absents d'AD |
| Taux de succes | Pourcentage de réussite |
| Date de traitement | Horodatage de l'exécution |
| Fichier source | Nom du fichier d'entrée |

---

## Gestion des erreurs

### Stratégie globale
Le script implémente une gestion d'erreurs à trois niveaux :

1. **Validation préventive** : Contrôles en amont
2. **Gestion locale** : Try-catch au niveau des fonctions
3. **Gestion globale** : Try-catch principal avec exit code

### Types d'erreurs gérées

#### 1. Erreurs de fichier
```powershell
# Fichier inexistant
"Fichier source non trouve: $FilePath"

# Format non supporté
"Format de fichier non supporte: $extension"

# Fichier vide
"Le fichier Excel ne contient aucune donnee"

# Structure invalide
"Colonnes 'UserName' et 'Hostname' requises"
```

#### 2. Erreurs Active Directory
```powershell
# Utilisateur inexistant
"ERREUR: Utilisateur non trouve dans AD"

# Problème de connectivité
"Unable to contact the server"

# Permissions insuffisantes
"Access denied"
```

#### 3. Erreurs de module
```powershell
# Module non trouvé
"Module 'ImportExcel' not found"

# Échec d'installation
"Failed to install module"
```

### Codes de sortie
- `0` : Exécution réussie
- `1` : Erreur critique (script interrompu)

### Logs d'erreur
Tous les erreurs sont tracées avec :
- Timestamp précis
- Niveau ERROR
- Message détaillé
- Contexte d'exécution

---

## Exemples d'utilisation

### 1. Utilisation basique
```powershell
# Exécution avec fichier d'entrée seulement
powershell.exe -ExecutionPolicy Bypass -File ".\credential-guard.ps1" -InputFile ".\FR-User-Credential-Guard.xlsx"
```

**Résultat** : Génère `export-traite-credential-guard.xlsx` dans le répertoire courant

### 2. Utilisation avec fichier de sortie personnalisé
```powershell
# Spécification du fichier de sortie
powershell.exe -ExecutionPolicy Bypass -File ".\credential-guard.ps1" -InputFile ".\donnees-utilisateurs.xlsx" -OutputFile ".\rapport-$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
```

### 3. Utilisation en lot (batch)
```batch
@echo off
set "SCRIPT_DIR=%~dp0"
set "INPUT_FILE=%SCRIPT_DIR%donnees\utilisateurs.xlsx"
set "OUTPUT_DIR=%SCRIPT_DIR%rapports"
set "OUTPUT_FILE=%OUTPUT_DIR%\rapport-%DATE:~6,4%%DATE:~3,2%%DATE:~0,2%.xlsx"

mkdir "%OUTPUT_DIR%" 2>nul

powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT_DIR%credential-guard.ps1" -InputFile "%INPUT_FILE%" -OutputFile "%OUTPUT_FILE%"

if %ERRORLEVEL% equ 0 (
    echo Traitement termine avec succes
    echo Rapport genere : %OUTPUT_FILE%
) else (
    echo Erreur lors du traitement
    exit /b 1
)
```

### 4. Utilisation programmée (Task Scheduler)
```powershell
# Création d'une tâche planifiée
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File 'C:\Scripts\credential-guard.ps1' -InputFile 'C:\Data\utilisateurs.xlsx' -OutputFile 'C:\Reports\rapport-quotidien.xlsx'"

$Trigger = New-ScheduledTaskTrigger -Daily -At "08:00"

$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName "Rapport Utilisateurs AD" -Action $Action -Trigger $Trigger -Settings $Settings
```

### 5. Intégration dans un pipeline CI/CD
```yaml
# Azure DevOps Pipeline
- task: PowerShell@2
  displayName: 'Génération rapport utilisateurs'
  inputs:
    targetType: 'filePath'
    filePath: '$(System.DefaultWorkingDirectory)/scripts/credential-guard.ps1'
    arguments: '-InputFile "$(Pipeline.Workspace)/data/users.xlsx" -OutputFile "$(Build.ArtifactStagingDirectory)/user-report.xlsx"'
    errorActionPreference: 'stop'
    warningPreference: 'continue'
```

---

## Dépannage

### Problèmes courants et solutions

#### 1. Erreur "Module 'ImportExcel' not found"
**Cause** : PowerShell Gallery inaccessible ou proxy réseau

**Solutions** :
```powershell
# Vérifier la connectivité PowerShell Gallery
Test-NetConnection powershellgallery.com -Port 443

# Configuration du proxy (si nécessaire)
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

# Installation manuelle
Install-Module ImportExcel -Force -Scope CurrentUser -Repository PSGallery
```

#### 2. Erreur "Unable to contact the server"
**Cause** : Problème de connectivité Active Directory

**Solutions** :
```powershell
# Test de connectivité au contrôleur de domaine
Test-ComputerSecureChannel -Verbose

# Vérification des services AD
Get-Service ADWS, Netlogon | Select-Object Name, Status

# Test d'authentification
Get-ADDomain -ErrorAction Stop
```

#### 3. Erreur "Access denied"
**Cause** : Permissions insuffisantes pour lire Active Directory

**Solutions** :
```powershell
# Vérification des permissions utilisateur
whoami /groups | findstr "Domain Users"

# Test d'accès en lecture
Get-ADUser $env:USERNAME -ErrorAction Stop
```

#### 4. Fichier Excel corrompu ou illisible
**Cause** : Format de fichier non standard ou corruption

**Solutions** :
```powershell
# Vérification de l'intégrité du fichier
try {
    $test = Import-Excel -Path $InputFile -HeaderName "Test" -StartRow 1 -EndRow 1
    Write-Host "Fichier lisible" -ForegroundColor Green
} catch {
    Write-Host "Erreur de lecture: $($_.Exception.Message)" -ForegroundColor Red
}

# Conversion vers format standard
# Ouvrir dans Excel et sauvegarder au format .xlsx
```

### Messages d'erreur détaillés

#### Format des logs d'erreur
```
[2025-07-15 14:30:25] [ERROR] ERREUR: Le fichier Excel ne contient aucune donnee
[2025-07-15 14:30:25] [ERROR] ERREUR: Colonnes 'UserName' et 'Hostname' requises
[2025-07-15 14:30:25] [ERROR] ERREUR: Utilisateur 'jdupont' non trouve dans AD
```

#### Codes d'erreur système
- **Exit Code 0** : Succès complet
- **Exit Code 1** : Erreur fatale, voir les logs pour détails

### Outils de diagnostic

#### Script de diagnostic
```powershell
# diagnostic-credential-guard.ps1
Write-Host "=== DIAGNOSTIC CREDENTIAL GUARD ===" -ForegroundColor Cyan

# Test des modules
Write-Host "`n1. Verification des modules..." -ForegroundColor Yellow
@("ImportExcel", "ActiveDirectory") | ForEach-Object {
    if (Get-Module -ListAvailable -Name $_) {
        Write-Host "MODULE OK $_" -ForegroundColor Green
    } else {
        Write-Host "MODULE MANQUANT $_" -ForegroundColor Red
    }
}

# Test Active Directory
Write-Host "`n2. Test Active Directory..." -ForegroundColor Yellow
try {
    $domain = Get-ADDomain -ErrorAction Stop
    Write-Host "CONNEXION AD OK - Domaine: $($domain.Name)" -ForegroundColor Green
} catch {
    Write-Host "ERREUR AD: $($_.Exception.Message)" -ForegroundColor Red
}

# Test PowerShell Gallery
Write-Host "`n3. Test PowerShell Gallery..." -ForegroundColor Yellow
try {
    $null = Find-Module ImportExcel -ErrorAction Stop
    Write-Host "POWERSHELL GALLERY OK" -ForegroundColor Green
} catch {
    Write-Host "POWERSHELL GALLERY INACCESSIBLE" -ForegroundColor Red
}
```

---

## Schéma de fonctionnement

### Vue d'ensemble du processus

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              CREDENTIAL GUARD SCRIPT                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─── PHASE 1: INITIALISATION ───┐     ┌─── PHASE 2: PRÉPARATION  ───┐
│                               │     │                             │
│  1. Démarrage du script       │────▶│  1. Installation modules    │
│  2. Validation des paramètres │     │     - ImportExcel           │
│  3. Logging initial           │     │     - ActiveDirectory       │
│                               │     │  2. Import des modules      │
└───────────────────────────────┘     └─────────────────────────────┘
                                                     │
                                                     ▼
┌─── PHASE 3: VALIDATION ───────┐     ┌─── PHASE 4: LECTURE ────────┐
│                               │     │                             │
│  1. Test existence fichier    │◀────│  1. Ouverture fichier Excel │
│  2. Validation format Excel   │     │  2. Vérification colonnes   │
│  3. Contrôle accessibilité    │     │  3. Filtrage données vides  │
│                               │     │                             │
└───────────────────────────────┘     └─────────────────────────────┘
                                                     │
                                                     ▼
┌─── PHASE 5: TRAITEMENT ───────────────────────────────────────────────┐
│                                                                       │
│  POUR CHAQUE UTILISATEUR:                                             │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    │
│  │ 1. Lire ligne   │───▶│ 2. Requête AD   │───▶│ 3. Traitement  │    │
│  │    UserName     │    │    Get-ADUser   │    │    - Si trouvé  │    │
│  │    Hostname     │    │    Description  │    │    - Si erreur  │    │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘    │
│                                                         │             │
│  ┌─────────────────┐    ┌─────────────────┐             │             │
│  │ 4. Mise à jour  │◀───│ 5. Ajout résult │◀───────────┘             │
│  │    Statistiques │    │    ou erreur    │                           │
│  └─────────────────┘    └─────────────────┘                           │
└───────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─── PHASE 6: GÉNÉRATION RAPPORT ────────────────────────────────────────┐
│                                                                        │
│  1. Export Excel principal:                                            │
│     ┌─────────────────────────────────────────────────────────────┐    │
│     │ ONGLET "Utilisateurs-AD"                                    │    │
│     │ - Nom Utilisateur                                           │    │
│     │ - Localisation (Description)                                │    │
│     │ - Numero de Poste                                           │    │
│     └─────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  2. Onglet statistiques:                                               │
│     ┌─────────────────────────────────────────────────────────────┐    │
│     │ ONGLET "Statistiques"                                       │    │
│     │ - Total utilisateurs traités                                │    │
│     │ - Utilisateurs trouvés dans AD                              │    │
│     │ - Utilisateurs non trouvés                                  │    │
│     │ - Taux de succès (%)                                        │    │
│     │ - Date de traitement                                        │    │
│     │ - Fichier source                                            │    │
│     └─────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  3. Formatage avancé (couleurs, styles, ajustement colonnes)           │
└────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                        ┌─────────────────────┐
                        │   SCRIPT TERMINÉ    │
                        │                     │
                        │ Exit Code 0: OK     │
                        │ Exit Code 1: Erreur │
                        └─────────────────────┘
```

### Points de contrôle et gestion d'erreurs

```
CONTRÔLES DE VALIDATION                    ACTIONS EN CAS D'ERREUR
─────────────────────                     ─────────────────────────

┌─ Paramètres manquants ─┐                  ┌─ Affichage aide ───────┐
│ InputFile obligatoire  │────── ERREUR ──▶│ Message d'utilisation   │
└────────────────────────┘                  └─ Exit Code 1 ──────────┘

┌─ Fichier inexistant ───┐                  ┌─ Log erreur ────────────┐
│ Test-Path InputFile    │────── ERREUR ──▶│ "Fichier non trouvé"     │
└────────────────────────┘                  └─ Exit Code 1  ──────────┘

┌─ Format invalide ──────┐                  ┌─ Log erreur ───────────┐
│ Extension .xlsx/.xls   │────── ERREUR ──▶│ "Format non supporté"   │
└────────────────────────┘                  └─ Exit Code 1 ──────────┘

┌─ Structure invalide ───┐                  ┌─ Log erreur ───────────┐
│ Colonnes UserName/Host │────── ERREUR ──▶│ "Colonnes manquantes"   │
└────────────────────────┘                  └─ Exit Code 1 ──────────┘

┌─ Utilisateur AD absent ┐                  ┌─ Compteur erreurs ──────┐
│ Get-ADUser échec       │────── WARNING ─▶│ Pas d'arrêt du script    │
└────────────────────────┘                  └─ Continue traitement ───┘

┌─ Aucun résultat ───────┐                  ┌─ Log erreur ───────────┐
│ 0 utilisateur trouvé   │────── ERREUR ──▶│ "Aucun utilisateur AD"  │
└────────────────────────┘                  └─ Exit Code 1 ──────────┘
```

### Flux de données détaillé

```
ENTRÉE                    TRAITEMENT                      SORTIE
──────                    ──────────                      ──────

FR-User-Credential        ┌─────────────────────────┐     export-traite-
-Guard.xlsx               │     SCRIPT PRINCIPAL    │     credential-guard.xlsx
                          │                         │
┌─────────────────┐       │  ┌───────────────────┐  │     ┌─────────────────────┐
│ UserName        │─────▶│  │ Get-UserADInfo     │ │────▶│ Nom Utilisateur     │
│ Hostname        │       │  │ (Active Directory)│  │     │ Localisation (Desc) │
│ [autres col.]   │       │  └───────────────────┘  │     │ Numero de Poste     │
└─────────────────┘       │                         │     └─────────────────────┘
                          │  ┌───────────────────┐  │            +
Exemples:                 │  │ Comptabilisation  │  │     ┌─────────────────────┐
- jdupont                 │  │ et statistiques   │  │     │ ONGLET STATISTIQUES │
- mmartin                 │  └───────────────────┘  │     │ - Total traités     │
- adurand                 │                         │     │ - Trouvés dans AD   │
                          └─────────────────────────┘     │ - Non trouvés       │
                                                          │ - Taux de succès    │
                                                          │ - Date traitement   │
                                                          └─────────────────────┘
```

### Architecture fonctionnelle

```
MODULES FONCTIONNELS DU SCRIPT
────────────────────────────────

┌─ MODULE LOGGING ──────────────┐    ┌─ MODULE INSTALLATION ─────────┐
│ • Write-Log (lignes 37-60)    │    │ • Install-RequiredModules     │
│ • Niveaux: INFO, SUCCESS,     │    │   (lignes 64-82)              │
│   WARNING, ERROR              │    │ • Gestion ImportExcel         │
│ • Format: [timestamp] [level] │    │ • Gestion ActiveDirectory     │
└───────────────────────────────┘    └───────────────────────────────┘

┌─ MODULE VALIDATION ───────────┐    ┌─ MODULE ACTIVE DIRECTORY ─────┐
│ • Test-InputFile              │    │ • Get-UserADInfo              │
│   (lignes 115-129)            │    │   (lignes 88-110)             │
│ • Contrôle existence          │    │ • Requête Get-ADUser          │
│ • Contrôle format Excel       │    │ • Gestion des erreurs AD      │
│ • Validation accessibilité    │    │ • Retour structuré            │
└───────────────────────────────┘    └───────────────────────────────┘

┌─ MODULE TRAITEMENT PRINCIPAL ─────────────────────────────────────────┐
│ • Process-UserCredentials (lignes 135-252)                            │
│ • Orchestration complète du processus                                 │
│ • Lecture Excel ──▶ Validation ──▶ Traitement ──▶ Export            │
└───────────────────────────────────────────────────────────────────────┘

┌─ MODULE REPORTING ────────────┐    ┌─ MODULE GESTION ERREURS ──────┐
│ • Export-Excel                │    │ • Try-Catch globaux           │
│ • Formatage avancé            │    │ • Gestion exit codes          │
│ • Création onglets multiples  │    │ • Logging centralisé          │
│ • Styles et couleurs          │    │ • Messages détaillés          │
└───────────────────────────────┘    └───────────────────────────────┘
```

---

## Support et maintenance

### Contact
- **Auteur** : Samuel Decarnelle
- **Version** : 1.1
- **Date de dernière modification** : Juillet 2025

---
