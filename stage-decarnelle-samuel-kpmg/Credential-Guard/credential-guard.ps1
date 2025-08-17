<#
.SYNOPSIS
    Script pour extraire les informations utilisateur d'Excel, enrichir avec les données AD et créer un export
.DESCRIPTION
    Ce script lit un fichier Excel contenant des noms d'utilisateurs et hostnames,
    interroge Active Directory pour récupérer les descriptions,
    et génère un nouveau fichier Excel avec les informations consolidées.
    Les dépendances sont automatiquement installées si nécessaire.
.PARAMETER InputFile
    Chemin vers le fichier Excel source
.PARAMETER OutputFile
    Chemin vers le fichier Excel de sortie
.NOTES
    Auteur: Samuel Decarnelle
    Version: 1.1
    Prérequis: Pas de Droits administrateur pour requis pour l'installation des modules nécessaires.
#>
# ================================================================================================
# EXEMPLE D'UTILISATION EN LIGNE DE COMMANDE
# ================================================================================================
# powershell.exe -ExecutionPolicy Bypass -File ".\credential-guard.ps1" -InputFile ".\FR-User-Credenial-Guard.xlsx"

# ================================================================================================
# DÉFINITION DES PARAMÈTRES D'ENTRÉE
# ================================================================================================
param(
    # Paramètre obligatoire : fichier Excel contenant les données utilisateurs
    # Format attendu : colonnes "UserName" et "Hostname" minimum
    [Parameter(Mandatory=$true)]
    [string]$InputFile,
    
    # Paramètre optionnel : nom du fichier de sortie
    # Si non spécifié, utilise un nom par défaut dans le répertoire courant
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "export-traite-credential-guard.xlsx"
)

# ================================================================================================
# FONCTION DE LOGGING
# ================================================================================================
# Cette fonction centralise l'affichage des messages avec timestamp et couleurs
# Permet un suivi clair de l'exécution du script
function Write-Log {
    param(
        [string]$Message,           # Message à afficher
        [string]$Level = "INFO"     # Niveau de log (INFO, SUCCESS, WARNING, ERROR)
    )
    
    # Génération du timestamp au format ISO pour traçabilité
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Attribution des couleurs selon le niveau de gravité
    $color = switch ($Level) {
        "INFO"    { "White" }       # Informations générales
        "SUCCESS" { "Green" }       # Opérations réussies
        "WARNING" { "Yellow" }      # Avertissements
        "ERROR"   { "Red" }         # Erreurs critiques
        default   { "White" }       # Fallback par défaut
    }
    
    # Affichage formaté : [timestamp] [niveau] message
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# ================================================================================================
# FONCTION D'INSTALLATION DES DÉPENDANCES
# ================================================================================================
# Installe et importe automatiquement les modules PowerShell requis
# Gère l'installation au niveau utilisateur pour éviter les problèmes de permissions
function Install-RequiredModules {
    # Liste des modules PowerShell essentiels au fonctionnement
    $modules = @(
        "ImportExcel",      # Module pour lire/écrire des fichiers Excel sans Office installé
        "ActiveDirectory"   # Module pour interroger Active Directory (RSAT requis)
    )
    
    # Traitement de chaque module requis
    foreach ($module in $modules) {
        # Vérification si le module est déjà installé sur le système
        if (!(Get-Module -ListAvailable -Name $module)) {
            # Installation automatique depuis PowerShell Gallery (scope utilisateur)
            # Force l'installation même si une version existe déjà
            Install-Module -Name $module -Force -Scope CurrentUser
        }
        
        # Import du module dans la session PowerShell courante
        # Force le rechargement pour s'assurer de la dernière version
        Import-Module -Name $module -Force
    }
}

# ================================================================================================
# FONCTION DE REQUÊTE ACTIVE DIRECTORY
# ================================================================================================
# Interroge Active Directory pour récupérer les informations d'un utilisateur
# Retourne un objet standardisé avec description et statut de recherche
function Get-UserADInfo {
    param([string]$Username)    # Nom d'utilisateur (SAMAccountName) à rechercher
    
    try {
        # Requête AD pour récupérer l'utilisateur et sa propriété Description
        # ErrorAction Stop force une exception en cas d'utilisateur non trouvé
        $adUser = Get-ADUser -Identity $Username -Properties Description -ErrorAction Stop
        
        # Construction de l'objet de retour pour utilisateur trouvé
        return @{
            # Gestion des descriptions vides ou nulles avec valeur par défaut
            Description = if ([string]::IsNullOrEmpty($adUser.Description)) { 
                "Aucune description" 
            } else { 
                $adUser.Description 
            }
            Found = $true    # Indicateur de succès de la recherche
        }
    }
    catch {
        # Gestion de tous les cas d'erreur (utilisateur inexistant, permissions, etc.)
        return @{
            Description = "ERREUR: Utilisateur non trouve dans AD"
            Found = $false   # Indicateur d'échec de la recherche
        }
    }
}

# ================================================================================================
# FONCTION DE VALIDATION DU FICHIER D'ENTRÉE
# ================================================================================================
# Valide l'existence et le format du fichier Excel source avant traitement
# Évite les erreurs en amont et fournit des messages d'erreur clairs
function Test-InputFile {
    param([string]$FilePath)    # Chemin complet vers le fichier à valider
    
    # Vérification de l'existence physique du fichier
    if (-not (Test-Path $FilePath)) {
        throw "Fichier source non trouve: $FilePath"
    }
    
    # Validation de l'extension pour s'assurer qu'il s'agit d'un fichier Excel
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($extension -notin @('.xlsx', '.xls')) {
        throw "Format de fichier non supporte: $extension"
    }
    
    # Si on arrive ici, le fichier est valide (pas de retour explicite nécessaire)
}

# ================================================================================================
# FONCTION PRINCIPALE DE TRAITEMENT
# ================================================================================================
# Orchestrateur principal : lit le fichier Excel, traite chaque utilisateur via AD,
# et génère un fichier Excel de sortie avec formatage et statistiques
function Process-UserCredentials {
    param(
        [string]$InputPath,     # Chemin du fichier Excel source
        [string]$OutputPath     # Chemin du fichier Excel de sortie
    )
    
    # -----------------------------------------------------------------------------------------
    # ÉTAPE 1: VALIDATION DU FICHIER SOURCE
    # -----------------------------------------------------------------------------------------
    Test-InputFile -FilePath $InputPath
    
    # -----------------------------------------------------------------------------------------
    # ÉTAPE 2: LECTURE ET VALIDATION DES DONNÉES EXCEL
    # -----------------------------------------------------------------------------------------
    # Import de toutes les données du fichier Excel (première feuille par défaut)
    $excelData = Import-Excel -Path $InputPath -ErrorAction Stop
    
    # Vérification que le fichier contient des données
    if (-not $excelData -or $excelData.Count -eq 0) {
        throw "Le fichier Excel ne contient aucune donnee"
    }
    
    # Validation de la structure : vérification des colonnes obligatoires
    $availableColumns = $excelData[0].PSObject.Properties.Name
    if ("UserName" -notin $availableColumns -or "Hostname" -notin $availableColumns) {
        throw "Colonnes 'UserName' et 'Hostname' requises"
    }
    
    # Filtrage des lignes avec des noms d'utilisateur vides ou uniquement des espaces
    $filteredData = $excelData | Where-Object { 
        -not [string]::IsNullOrWhiteSpace($_.UserName) 
    }
    
    # Vérification qu'il reste des données après filtrage
    if (-not $filteredData -or $filteredData.Count -eq 0) {
        throw "Aucune donnee utilisateur valide trouvee"
    }
        
    # -----------------------------------------------------------------------------------------
    # ÉTAPE 3: TRAITEMENT DES UTILISATEURS ET REQUÊTES AD
    # -----------------------------------------------------------------------------------------
    # Initialisation des structures de données pour les résultats
    $results = @()              # Tableau pour stocker uniquement les utilisateurs trouvés
    $processedCount = 0         # Compteur total d'utilisateurs traités
    $successCount = 0           # Compteur d'utilisateurs trouvés dans AD
    $errorCount = 0             # Compteur d'utilisateurs non trouvés
    
    # Boucle de traitement pour chaque ligne du fichier Excel
    foreach ($row in $filteredData) {
        $processedCount++
        
        # Requête Active Directory pour l'utilisateur courant
        $adInfo = Get-UserADInfo -Username $row.UserName
        
        # Traitement selon le résultat de la requête AD
        if ($adInfo.Found) {
            # Utilisateur trouvé : ajout aux résultats finaux
            $successCount++
            $results += [PSCustomObject]@{
                'Nom Utilisateur'           = $row.UserName
                'Localisation (Description)' = $adInfo.Description
                'Numero de Poste'           = $row.Hostname
            }
        } else {
            # Utilisateur non trouvé : incrémentation du compteur d'erreurs seulement
            # (pas d'ajout aux résultats pour garder un export propre)
            $errorCount++
        }
    }
    
    # Vérification qu'au moins un utilisateur a été trouvé
    if ($results.Count -eq 0) {
        throw "Aucun utilisateur trouve dans AD"
    }
    
    # -----------------------------------------------------------------------------------------
    # ÉTAPE 4: GÉNÉRATION DU FICHIER EXCEL DE SORTIE
    # -----------------------------------------------------------------------------------------
    # Suppression du fichier de sortie existant s'il existe
    if (Test-Path $OutputPath) { 
        Remove-Item $OutputPath -Force 
    }
    
    # Export des résultats vers Excel avec formatage de base
    $results | Export-Excel -Path $OutputPath -WorksheetName "Utilisateurs-AD" -AutoSize -FreezeTopRow -TableStyle Medium2
    
    # -----------------------------------------------------------------------------------------
    # ÉTAPE 5: FORMATAGE AVANCÉ ET AJOUT DES STATISTIQUES
    # -----------------------------------------------------------------------------------------
    # Application d'un formatage professionnel et ajout d'un onglet statistiques
    try {
        # Ouverture du fichier Excel pour formatage avancé
        $excel = Open-ExcelPackage -Path $OutputPath
        $worksheet = $excel.Workbook.Worksheets["Utilisateurs-AD"]
        
        # FORMATAGE DES EN-TÊTES
        # Application d'un style professionnel aux colonnes d'en-tête
        $headerRange = $worksheet.Cells[1, 1, 1, 3]  # Ligne 1, colonnes 1 à 3
        $headerRange.Style.Font.Bold = $true         # Texte en gras
        $headerRange.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
        $headerRange.Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::LightBlue)
        
        # CRÉATION DE L'ONGLET STATISTIQUES
        # Ajout d'un onglet dédié aux métriques de traitement
        $statsWorksheet = $excel.Workbook.Worksheets.Add("Statistiques")
        
        # Construction des données statistiques
        @(
            [PSCustomObject]@{Metrique = "Total utilisateurs traites"; Valeur = $processedCount},
            [PSCustomObject]@{Metrique = "Utilisateurs trouves dans AD"; Valeur = $successCount},
            [PSCustomObject]@{Metrique = "Utilisateurs non trouves"; Valeur = $errorCount},
            [PSCustomObject]@{Metrique = "Taux de succes"; Valeur = "$([math]::Round(($successCount / $processedCount) * 100, 1))%"},
            [PSCustomObject]@{Metrique = "Date de traitement"; Valeur = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")},
            [PSCustomObject]@{Metrique = "Fichier source"; Valeur = [System.IO.Path]::GetFileName($InputPath)}
        ) | Export-Excel -ExcelPackage $excel -WorksheetName "Statistiques" -AutoSize -TableStyle Medium6
        
        # Fermeture et sauvegarde du fichier Excel
        Close-ExcelPackage $excel
    }
    catch {
        # En cas d'erreur de formatage, on continue (le fichier de base existe)
        # Ceci évite que le script échoue pour des problèmes cosmétiques
    }
}

# ================================================================================================
# POINT D'ENTRÉE PRINCIPAL DU SCRIPT
# ================================================================================================
# Orchestrateur global avec gestion d'erreurs centralisée
# Assure l'exécution séquentielle et le reporting d'état
try {
    # -----------------------------------------------------------------------------------------
    # PHASE 1: INITIALISATION
    # -----------------------------------------------------------------------------------------
    Write-Log "Script demarre" "INFO"
    
    # -----------------------------------------------------------------------------------------
    # PHASE 2: PRÉPARATION DE L'ENVIRONNEMENT
    # -----------------------------------------------------------------------------------------
    # Installation et import des dépendances PowerShell
    # Cette étape peut prendre du temps lors de la première exécution
    Install-RequiredModules
    
    # -----------------------------------------------------------------------------------------
    # PHASE 3: TRAITEMENT PRINCIPAL
    # -----------------------------------------------------------------------------------------
    # Traitement complet : lecture Excel → requêtes AD → export formaté
    Process-UserCredentials -InputPath $InputFile -OutputPath $OutputFile
    
    # -----------------------------------------------------------------------------------------
    # PHASE 4: FINALISATION
    # -----------------------------------------------------------------------------------------
    Write-Log "Script termine" "SUCCESS"
    
} catch {
    # -----------------------------------------------------------------------------------------
    # GESTION GLOBALE DES ERREURS
    # -----------------------------------------------------------------------------------------
    # Capture de toute erreur non gérée et affichage avec contexte
    Write-Log "ERREUR: $($_.Exception.Message)" "ERROR"
    
    # Code de sortie non-zéro pour indiquer l'échec aux scripts appelants
    exit 1
}
