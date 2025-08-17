# =============================================================================
# SCRIPT EOS/EOL CHECKER AVANCE - KPMG PARC INFORMATIQUE
# Créateur : Samuel Decarnelle (Stage KPMG)
# =============================================================================
# Version 2.0 - Avec API endoflife.date
# 
# DESCRIPTION:
# Ce script analyse un inventaire Excel de machines et vérifie automatiquement
# le statut End-of-Life (EOL) et End-of-Support (EOS) de leurs systèmes d'exploitation
# en utilisant l'API publique endoflife.date. Il génère des rapports détaillés
# en Excel et CSV avec des alertes précoces pour les machines approchant EOL/EOS.
#
# FONCTIONNALITES PRINCIPALES:
# - Lecture automatique d'un fichier Excel d'inventaire de machines
# - Interrogation en temps réel de l'API endoflife.date pour chaque type d'OS
# - Normalisation intelligente des versions d'OS (ex: "22h2" → "22H2")
# - Optimisation des appels API par groupement OS+Version (réduit drastiquement les requêtes)
# - Gestion intelligente du rate limiting avec retry automatique
# - Inclusion de TOUTES les machines (analysables et non-analysables)
# - Génération de rapports Excel multi-feuilles avec résumés détaillés
# - Alertes précoces configurables (par défaut 180 jours avant EOL/EOS)
# - Support des versions imprecises avec signalement approprié
#
# EXECUTION:
# powershell -ExecutionPolicy Bypass -File ".\EOS-Checker.ps1" -ExcelPath "MDE_AllDevices_20250625.xlsx"
#
# PARAMETRES OPTIONNELS:
# -WarningDays 180    : Alerte si EOL/EOS dans moins de 180 jours (défaut: 365)
# -BatchMode          : Mode batch avec rate limiting agressif pour gros datasets
# -UseCache           : Active le cache API (désactivé par défaut pour données fraîches)
# =============================================================================

# SECTION 1: PARAMETRES D'ENTREE
# =============================================================================
# Définition des paramètres d'entrée du script avec validation et valeurs par défaut
# =============================================================================
param(
    # PARAMETRE OBLIGATOIRE: Chemin vers le fichier Excel d'inventaire
    [Parameter(Mandatory=$true, HelpMessage="Chemin vers le fichier Excel contenant l'inventaire des machines")]
    [string]$ExcelPath,
    
    # PARAMETRE OPTIONNEL: Activation du cache API
    # Par défaut désactivé pour garantir des données fraîches à chaque exécution
    # Peut être activé pour accélérer les tests répétés sur le même dataset
    [switch]$UseCache = $false,
    
    # PARAMETRE OPTIONNEL: Seuil d'alerte précoce en jours
    # Définit combien de jours avant EOL/EOS une machine doit être signalée comme "BIENTOT EOL/EOS"
    # Valeur par défaut: 180 jours (6 mois) pour permettre la planification des migrations
    [int]$WarningDays = 180,
    
    # PARAMETRE OPTIONNEL: Filtrage des résultats d'affichage
    # Par défaut: false (montre toutes les machines pour visibilité complète)
    # Si true: n'affiche que les machines avec problèmes (EOL/EOS/BIENTOT/NON ANALYSABLE)
    [switch]$ShowOnlyProblems = $false,
    
    # PARAMETRE OPTIONNEL: Mode batch pour gros datasets
    # Active un rate limiting plus agressif (pauses plus longues) pour éviter la surcharge de l'API
    # Recommandé pour des inventaires de plus de 1000 machines avec beaucoup de types d'OS différents
    [switch]$BatchMode = $false
)

# SECTION 2: VARIABLES GLOBALES ET CONFIGURATION
# =============================================================================
# Définition des variables globales utilisées dans tout le script
# =============================================================================

# TIMER GLOBAL: Démarrage du chronomètre pour mesurer le temps total d'exécution
# Ce timer mesure la durée complète du script, de l'initialisation à la fin
$global:ScriptStartTime = Get-Date
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "SCRIPT EOS/EOL CHECKER - DEMARRAGE" -ForegroundColor Cyan  
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Heure de démarrage: $($global:ScriptStartTime.ToString('dd/MM/yyyy HH:mm:ss'))" -ForegroundColor Green
Write-Host ""

# CACHE API GLOBAL: Stockage des résultats d'API pour éviter les appels répétés
# Structure: Clé = "ProductName-Version", Valeur = Objet avec données lifecycle
# Exemple: "windows-10" => { EOL_Date, EOS_Date, Is_EOL, Is_EOS, etc. }
# Ce cache est persistant pendant toute l'exécution du script, permettant d'optimiser
# drastiquement les performances quand plusieurs machines ont le même OS+Version
$global:ApiCache = @{}

# URL DE BASE DE L'API: Point d'entrée de l'API publique endoflife.date
# Documentation complète: https://endoflife.date/docs/api
# Format des endpoints: https://endoflife.date/api/{product}.json
# Exemples: https://endoflife.date/api/windows.json, https://endoflife.date/api/ubuntu.json
$global:ApiBaseUrl = "https://endoflife.date/api"

# SECTION 3: FONCTION DE MAPPING DES NOMS D'OS VERS L'API
# =============================================================================
# Fonction de conversion des noms d'OS de l'inventaire vers les identifiants API
# =============================================================================
#
# OBJECTIF:
# Les noms d'OS dans les fichiers Excel d'inventaire ne correspondent pas exactement
# aux identifiants utilisés par l'API endoflife.date. Cette fonction fait le mapping
# entre les deux formats pour permettre les appels API corrects.
#
# EXEMPLES DE CONVERSION:
# "Windows10" (inventaire) → "windows" (API)
# "WindowsServer2019" (inventaire) → "windows-server" (API)
# "Ubuntu" (inventaire) → "ubuntu" (API)
#
# LOGIQUE DE RECHERCHE:
# 1. Recherche exacte dans le dictionnaire de mapping
# 2. Recherche par correspondance partielle (wildcards)
# 3. Recherche par patterns génériques si aucune correspondance exacte
#
function Get-ApiProductName {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OSName  # Nom de l'OS tel qu'il apparaît dans le fichier Excel
    )
    
    # DICTIONNAIRE DE MAPPING: Noms d'inventaire → Identifiants API
    # Basé sur la documentation officielle de l'API endoflife.date
    # Référence: https://endoflife.date/docs/api/products
    $mapping = @{
        # FAMILLE WINDOWS DESKTOP: Toutes les versions pointent vers l'endpoint "windows"
        # L'API endoflife.date utilise un seul endpoint pour toutes les versions de Windows client
        "Windows10" = "windows"      # Windows 10 (format sans espace)
        "Windows11" = "windows"      # Windows 11 (format sans espace)
        "Windows10WVD" = "windows"   # Windows Virtual Desktop basé sur Windows 10
        "Windows7" = "windows"       # Windows 7 (legacy, mais encore présent dans certains parcs)
        "Windows8" = "windows"       # Windows 8 (legacy)
        "Windows8.1" = "windows"     # Windows 8.1 (legacy)
        "WindowsVista" = "windows"   # Windows Vista (legacy)
        "WindowsXP" = "windows"      # Windows XP (legacy, critique si encore présent)
        
        # FORMATS ALTERNATIFS WINDOWS DESKTOP (avec espaces, parfois présents selon la source)
        # Ces entrées gèrent les variations possibles de nommage
        #"Windows 10" = "windows"
        #"Windows 11" = "windows"
        #"Windows 7" = "windows"
        #"Windows 8" = "windows"
        #"Windows 8.1" = "windows"
        #"Windows Vista" = "windows"
        #"Windows XP" = "windows"
        
        # FAMILLE WINDOWS SERVER: Toutes les versions pointent vers l'endpoint "windows-server"
        # L'API utilise un endpoint séparé pour les versions serveur de Windows
        "WindowsServer2022" = "windows-server"     # Windows Server 2022 (dernier LTS)
        "WindowsServer2019" = "windows-server"     # Windows Server 2019 (LTS précédent)
        "WindowsServer2016" = "windows-server"     # Windows Server 2016 (encore supporté)
        "WindowsServer2012" = "windows-server"     # Windows Server 2012 (attention EOL proche)
        "WindowsServer2012R2" = "windows-server"   # Windows Server 2012 R2 (attention EOL proche)
        "WindowsServer2008" = "windows-server"     # Windows Server 2008 (EOL - critique)
        "WindowsServer2008R2" = "windows-server"   # Windows Server 2008 R2 (EOL - critique)
        "WindowsServer2003" = "windows-server"     # Windows Server 2003 (EOL depuis longtemps - très critique)
        
        # FORMATS ALTERNATIFS WINDOWS SERVER (avec espaces)
        #"Windows Server 2022" = "windows-server"
        #"Windows Server 2019" = "windows-server"
        #"Windows Server 2016" = "windows-server"
        #"Windows Server 2012" = "windows-server"
        #"Windows Server 2012 R2" = "windows-server"
        #"Windows Server 2008" = "windows-server"
        #"Windows Server 2008 R2" = "windows-server"
        #"Windows Server 2003" = "windows-server"
        
        # DISTRIBUTIONS LINUX: Chaque distribution a son propre endpoint API
        "Ubuntu" = "ubuntu"                          # Ubuntu (très courant en entreprise)
        "CentOS" = "centos"                          # CentOS (attention: projet EOL en 2024)
        "RHEL" = "rhel"                             # Red Hat Enterprise Linux
        "RedHatEnterpriseLinux" = "rhel"            # Format alternatif RHEL
        "Red Hat Enterprise Linux" = "rhel"         # Format avec espaces
        "Debian" = "debian"                         # Debian (base de nombreuses distributions)
        
        # SYSTEMES APPLE: Endpoint unifié pour macOS
        "macOS" = "macos"                           # macOS moderne
        "Mac OS X" = "macos"                        # Format legacy Mac OS X
        
        # VIRTUALISATION VMWARE: Endpoint pour vSphere/ESXi
        "VMware vSphere" = "vmware-vsphere"         # VMware vSphere (hyperviseur)
        "VMware ESXi" = "vmware-vsphere"            # VMware ESXi (composant de vSphere)
    }
    
    # ETAPE 1: RECHERCHE EXACTE dans le dictionnaire de mapping
    # Vérifie d'abord si le nom d'OS correspond exactement à une entrée du dictionnaire
    if ($mapping.ContainsKey($OSName)) {
        Write-Host "DEBUG: Mapping exact trouvé pour '$OSName' → '$($mapping[$OSName])'" -ForegroundColor DarkGray
        return $mapping[$OSName]
    }
    
    # ETAPE 2: RECHERCHE PARTIELLE par wildcards
    # Si pas de correspondance exacte, cherche si le nom d'OS contient une clé du dictionnaire
    # Exemple: "Windows10Pro" contiendrait "Windows10" et serait mappé vers "windows"
    foreach ($key in $mapping.Keys) {
        if ($OSName -like "*$key*") {
            Write-Host "DEBUG: Mapping partiel trouvé '$OSName' contient '$key' → '$($mapping[$key])'" -ForegroundColor DarkGray
            return $mapping[$key]
        }
    }
    
    # ETAPE 3: RECHERCHE PAR PATTERNS GENERIQUES
    # Si aucune correspondance dans le dictionnaire, utilise des patterns génériques
    # pour essayer de deviner le bon endpoint API
    Write-Host "DEBUG: Aucun mapping exact, tentative de reconnaissance par pattern pour '$OSName'" -ForegroundColor DarkGray
    
    # Pattern Windows Server (priorité haute car plus spécifique que Windows client)
    if ($OSName -like "*WindowsServer*" -or $OSName -like "*Windows*Server*") { 
        Write-Host "DEBUG: Pattern Windows Server détecté → 'windows-server'" -ForegroundColor DarkGray
        return "windows-server" 
    }
    
    # Pattern Windows client (après avoir exclu les serveurs)
    if ($OSName -like "*Windows*") { 
        Write-Host "DEBUG: Pattern Windows client détecté → 'windows'" -ForegroundColor DarkGray
        return "windows" 
    }
    
    # Patterns Linux
    if ($OSName -like "*Ubuntu*") { 
        Write-Host "DEBUG: Pattern Ubuntu détecté → 'ubuntu'" -ForegroundColor DarkGray
        return "ubuntu" 
    }
    if ($OSName -like "*CentOS*") { 
        Write-Host "DEBUG: Pattern CentOS détecté → 'centos'" -ForegroundColor DarkGray
        return "centos" 
    }
    if ($OSName -like "*RHEL*" -or $OSName -like "*RedHat*" -or $OSName -like "*Red Hat*") { 
        Write-Host "DEBUG: Pattern RHEL détecté → 'rhel'" -ForegroundColor DarkGray
        return "rhel" 
    }
    if ($OSName -like "*Debian*") { 
        Write-Host "DEBUG: Pattern Debian détecté → 'debian'" -ForegroundColor DarkGray
        return "debian" 
    }
    
    # Patterns macOS
    if ($OSName -like "*macOS*" -or $OSName -like "*Mac OS*") { 
        Write-Host "DEBUG: Pattern macOS détecté → 'macos'" -ForegroundColor DarkGray
        return "macos" 
    }
    
    # AUCUNE CORRESPONDANCE TROUVEE
    # L'OS n'est pas reconnu et ne peut pas être analysé via l'API
    Write-Host "ATTENTION: OS non reconnu '$OSName' - ne sera pas analysé" -ForegroundColor Yellow
    return $null
}

# SECTION 4: FONCTION D'EXTRACTION ET NORMALISATION DES VERSIONS D'OS
# =============================================================================
# Fonction de nettoyage et normalisation des versions d'OS pour les appels API
# =============================================================================
#
# OBJECTIF:
# Les versions d'OS dans les inventaires peuvent être dans différents formats :
# - Versions explicites : "10.0.19042", "22H2", "20.04"
# - Versions dans le nom : "Windows10", "WindowsServer2019"
# - Versions mal formatées : "22h2" (minuscule), "2012 R2" (espace)
#
# Cette fonction normalise tout vers le format attendu par l'API endoflife.date
#
# EXEMPLES DE NORMALISATION:
# "22h2" → "22H2" (Windows feature updates)
# "2012 R2" → "2012-r2" (Windows Server)
# "Windows10" → "10" (extraction depuis le nom)
# "10.0.19042" → "10.0.19042" (version build complète)
#
function Get-OSVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OSName,     # Nom de l'OS (ex: "Windows10", "Ubuntu")
        
        [Parameter(Mandatory=$false)]
        [string]$Version     # Version explicite (ex: "22H2", "20.04", peut être vide)
    )
    
    # ETAPE 1: TRAITEMENT DE LA VERSION EXPLICITE
    # Si une version explicite est fournie, on la traite en priorité
    if (![string]::IsNullOrEmpty($Version)) {
        $cleanVersion = $Version.Trim()
        
        # CAS SPECIAL: Versions Windows avec format "22h2", "21h1", etc.
        # L'API endoflife.date attend le format "22H2" (majuscule)
        if ($cleanVersion -match '(\d+)h(\d+)') {
            $normalizedVersion = "$($matches[1])H$($matches[2])"
            Write-Host "DEBUG: Version Windows normalisée '$Version' → '$normalizedVersion'" -ForegroundColor DarkGray
            return $normalizedVersion
        }
        
        # NETTOYAGE GENERAL: Supprime les caractères non-numériques sauf les points
        # Garde les formats comme "10.0.19042", "20.04", "8.1"
        $cleanVersion = $cleanVersion -replace '[^\d\.]', ''
        if (![string]::IsNullOrEmpty($cleanVersion)) {
            Write-Host "DEBUG: Version nettoyée '$Version' → '$cleanVersion'" -ForegroundColor DarkGray
            return $cleanVersion
        }
    }
    
    # ETAPE 2: EXTRACTION DE VERSION DEPUIS LE NOM DE L'OS
    # Si pas de version explicite, essaie d'extraire la version du nom de l'OS
    Write-Host "DEBUG: Tentative d'extraction de version depuis le nom OS '$OSName'" -ForegroundColor DarkGray
    
    # PATTERNS DE RECHERCHE: Ordre de priorité du plus spécifique au plus général
    # Plus un pattern est spécifique, plus il a de chances d'être correct
    $versionPatterns = @(
        '(\d+H\d+)',            # Format Windows Feature Update (ex: 22H2, 21H1) - PRIORITE HAUTE
        '(\d+h\d+)',            # Format Windows Feature Update minuscule (ex: 22h2) - PRIORITE HAUTE
        '(\d+\.\d+\.\d+)',      # Format version complète (ex: 10.0.19042, 18.04.5) - PRIORITE MOYENNE
        '(\d+\.\d+)',           # Format version majeure.mineure (ex: 20.04, 8.1) - PRIORITE MOYENNE
        '(\d{4}\s*R2)',         # Format Windows Server R2 (ex: 2012 R2, 2008 R2) - PRIORITE MOYENNE
        '(\d{4})',              # Format année (ex: 2019, 2016) - PRIORITE MOYENNE
        '(\d+)'                 # Juste un numéro (ex: 10, 7) - PRIORITE BASSE
    )
    
    # RECHERCHE PAR PATTERNS
    foreach ($pattern in $versionPatterns) {
        if ($OSName -match $pattern) {
            $extractedVersion = $matches[1].Trim()
            Write-Host "DEBUG: Version extraite avec pattern '$pattern': '$extractedVersion'" -ForegroundColor DarkGray
            
            # NORMALISATION POST-EXTRACTION
            # Applique les règles de normalisation spécifiques à chaque type de version
            $normalizedVersion = switch -Regex ($extractedVersion) {
                # Windows Feature Updates
                '^\d+h\d+$' { 
                    # Convertit "22h2" en "22H2"
                    if ($extractedVersion -match '(\d+)h(\d+)') {
                        "$($matches[1])H$($matches[2])"
                    }
                }
                '^\d+H\d+$' { 
                    # Déjà au bon format
                    $extractedVersion 
                }
                
                # Windows Client
                '^10$' { "10" }     # Windows 10
                '^11$' { "11" }     # Windows 11
                '^7$' { "7" }       # Windows 7
                '^8\.1$' { "8.1" }  # Windows 8.1
                '^8$' { "8" }       # Windows 8
                
                # Windows Server
                '^2022$' { "2022" }         # Windows Server 2022
                '^2019$' { "2019" }         # Windows Server 2019
                '^2016$' { "2016" }         # Windows Server 2016
                '^2012 R2$' { "2012-r2" }   # Windows Server 2012 R2 (format API)
                '^2012$' { "2012" }         # Windows Server 2012
                '^2008 R2$' { "2008-r2" }   # Windows Server 2008 R2 (format API)
                '^2008$' { "2008" }         # Windows Server 2008
                
                # Par défaut: garde la version telle quelle
                default { $extractedVersion }
            }
            
            Write-Host "DEBUG: Version normalisée finale: '$normalizedVersion'" -ForegroundColor DarkGray
            return $normalizedVersion
        }
    }
    
    # ETAPE 3: MAPPING DIRECT POUR OS SANS NUMERO DANS LE NOM
    # Certains OS ont des noms qui ne contiennent pas explicitement leur version
    Write-Host "DEBUG: Tentative de mapping direct pour OS '$OSName'" -ForegroundColor DarkGray
    
    # Mapping direct nom → version
    $directMapping = @{
        "Windows10" = "10"           # Windows 10
        "Windows11" = "11"           # Windows 11  
        "Windows10WVD" = "10"        # Windows Virtual Desktop (basé sur Windows 10)
    }
    
    if ($directMapping.ContainsKey($OSName)) {
        $mappedVersion = $directMapping[$OSName]
        Write-Host "DEBUG: Mapping direct trouvé '$OSName' → '$mappedVersion'" -ForegroundColor DarkGray
        return $mappedVersion
    }
    
    # ETAPE 4: TRAITEMENT SPECIAL POUR WINDOWS SERVER
    # Extraction d'année depuis le nom pour les serveurs Windows
    if ($OSName -like "WindowsServer*") {
        if ($OSName -match "(\d{4})") {
            $serverYear = $matches[1]
            Write-Host "DEBUG: Année Windows Server extraite '$OSName' → '$serverYear'" -ForegroundColor DarkGray
            return $serverYear
        }
    }
    
    # ECHEC: AUCUNE VERSION EXTRACTIBLE
    # L'OS est reconnu mais sa version ne peut pas être déterminée
    Write-Host "ATTENTION: Impossible d'extraire une version pour '$OSName'" -ForegroundColor Yellow
    return $null
}

# SECTION 5: FONCTION D'INTERROGATION DE L'API AVEC GESTION AVANCEE
# =============================================================================
# Fonction principale d'appel à l'API endoflife.date avec retry logic et rate limiting
# =============================================================================
#
# OBJECTIF:
# Cette fonction est le cœur de l'interrogation API. Elle gère :
# - Le cache pour éviter les appels répétés
# - Le rate limiting pour respecter les limites de l'API
# - La logique de retry en cas d'erreur temporaire
# - L'analyse et parsing des réponses JSON de l'API
# - La gestion des versions trop génériques
# - Le calcul des jours restants jusqu'à EOL/EOS
#
# FLOW LOGIQUE:
# 1. Vérification du cache
# 2. Rate limiting et retry loop
# 3. Appel HTTP à l'API
# 4. Parsing de la réponse et recherche de la version
# 5. Validation de la précision de la version
# 6. Parsing des dates EOL/EOS
# 7. Calculs des jours restants
# 8. Mise en cache du résultat
#
function Get-ProductLifecycle {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProductName,    # Nom du produit API (ex: "windows", "ubuntu")
        
        [Parameter(Mandatory=$true)]
        [string]$Version         # Version normalisée (ex: "22H2", "20.04")
    )
    
    # ETAPE 1: VERIFICATION DU CACHE
    # Le cache est toujours actif pour éviter les appels API répétés sur les mêmes OS+Version
    # Clé de cache: "ProductName-Version" (ex: "windows-22H2", "ubuntu-20.04")
    $cacheKey = "$ProductName-$Version"
    if ($global:ApiCache.ContainsKey($cacheKey)) {
        Write-Host "CACHE: Utilisation du résultat mis en cache pour $ProductName $Version" -ForegroundColor DarkGray
        return $global:ApiCache[$cacheKey]
    }
    
    # ETAPE 2: CONFIGURATION DU RETRY LOGIC
    # L'API peut être temporairement indisponible ou rate-limitée
    # On implémente un retry avec exponential backoff pour la fiabilité
    $maxRetries = 3                    # Nombre maximum de tentatives
    $baseDelay = 2                     # Délai de base en secondes pour le retry
    $retryCount = 0                    # Compteur de tentatives actuel
    
    # BOUCLE DE RETRY: Continue jusqu'à succès ou épuisement des tentatives
    while ($retryCount -le $maxRetries) {
        try {
            # ETAPE 3: RATE LIMITING INTELLIGENT
            # Gestion des délais entre appels pour respecter les limites de l'API
            if ($retryCount -gt 0) {
                # EXPONENTIAL BACKOFF pour les retries: 2s, 4s, 8s
                $delay = $baseDelay * [Math]::Pow(2, $retryCount - 1)
                Write-Host "RETRY: Rate limit ou erreur détectée. Attente de $delay secondes (tentative $retryCount/$maxRetries)" -ForegroundColor Yellow
                Start-Sleep -Seconds $delay
            } else {
                # DELAI MINIMAL entre appels pour éviter la surcharge de l'API
                # Mode batch: plus conservateur pour gros datasets
                $delay = if ($BatchMode) { 2000 } else { 1000 }  # milliseconds
                Start-Sleep -Milliseconds $delay
            }
            
            # ETAPE 4: CONSTRUCTION DE L'URL D'API
            # Format: https://endoflife.date/api/{product}.json
            $apiUrl = "$global:ApiBaseUrl/$ProductName.json"
            
            Write-Host "API: Interrogation de $apiUrl pour version '$Version' (tentative $($retryCount + 1))" -ForegroundColor DarkGray
            
            # ETAPE 5: CONFIGURATION DE LA REQUETE HTTP
            # Headers recommandés pour une API publique
            $headers = @{
                'User-Agent' = 'KPMG-EOS-Checker/2.0'    # Identification du client
                'Accept' = 'application/json'              # Format de réponse attendu
            }
            
            # ETAPE 6: APPEL HTTP AVEC TIMEOUT
            # Timeout de 30 secondes pour éviter les blocages
            $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
            
            # ETAPE 7: RECHERCHE DE LA VERSION DANS LA REPONSE
            # L'API renvoie un tableau d'objets, un par version supportée
            # Chaque objet contient: cycle, eol, support, latest, etc.
            $versionInfo = $null
            
            Write-Host "DEBUG: API a retourné $($response.Count) versions pour $ProductName" -ForegroundColor DarkGray
            
            # RECHERCHE MULTI-CRITERES pour matcher la version
            # Essaie plusieurs champs car les APIs varient dans leur structure
            foreach ($item in $response) {
                # Critères de matching (du plus précis au plus large):
                $isMatch = (
                    $item.cycle -eq $Version -or                    # Match exact sur le cycle
                    $item.cycle -like "*$Version*" -or              # Cycle contient la version
                    $item.latest -like "*$Version*" -or             # Version latest contient notre version
                    $Version -like "*$($item.cycle)*"               # Notre version contient le cycle
                )
                
                if ($isMatch) {
                    $versionInfo = $item
                    Write-Host "DEBUG: Version trouvée - Cycle: '$($item.cycle)', Latest: '$($item.latest)'" -ForegroundColor DarkGray
                    break
                }
            }
            
            # FALLBACK: Si version exacte pas trouvée, utilise la version par défaut
            # Cela arrive souvent avec des versions très spécifiques
            if (-not $versionInfo -and $response.Count -gt 0) {
                Write-Host "ATTENTION: Version exacte '$Version' non trouvée pour $ProductName, utilisation de la version générique" -ForegroundColor Yellow
                $versionInfo = $response[0]  # Prend la première version (souvent la plus récente)
            }
            
            # ETAPE 8: TRAITEMENT DES DONNEES DE VERSION
            if ($versionInfo) {
                
                # ETAPE 8A: VALIDATION DE LA PRECISION DE LA VERSION
                # Certaines versions sont trop génériques pour donner des dates fiables
                $isVersionTooGeneric = $false
                $dateUnavailableReason = $null
                
                # VERIFICATION SPECIALE pour les distributions Linux
                # Ces OS nécessitent des versions précises (ex: "20.04" pas juste "20")
                if ($ProductName -eq "ubuntu" -and $Version -match '^\d+$') {
                    $isVersionTooGeneric = $true
                    Write-Host "ATTENTION: Version Ubuntu trop générique '$Version' (attendu format comme '20.04')" -ForegroundColor Yellow
                } elseif ($ProductName -eq "centos" -and $Version -match '^\d+$') {
                    $isVersionTooGeneric = $true
                    Write-Host "ATTENTION: Version CentOS trop générique '$Version' (attendu format comme '7.9')" -ForegroundColor Yellow
                } elseif ($ProductName -eq "rhel" -and $Version -match '^\d+$') {
                    $isVersionTooGeneric = $true
                    Write-Host "ATTENTION: Version RHEL trop générique '$Version' (attendu format comme '8.4')" -ForegroundColor Yellow
                }
                
                # ASSIGNATION DU MOTIF pour versions trop génériques
                if ($isVersionTooGeneric) {
                    $dateUnavailableReason = "Date not available due to version not precised"
                    Write-Host "INFO: Dates EOL/EOS non assignées - version insuffisamment précise" -ForegroundColor DarkGray
                }
                
                # ETAPE 8B: PARSING DES DATES EOL/EOS
                # L'API utilise le format ISO 8601 (YYYY-MM-DD) pour les dates
                $currentDate = Get-Date
                $eolDate = $null      # End of Life
                $eosDate = $null      # End of Support
                
                # PARSING DE LA DATE EOL (End of Life)
                # La date EOL est généralement dans le champ 'eol'
                if (!$isVersionTooGeneric) {
                    if ($versionInfo.eol -and $versionInfo.eol -ne $false -and $versionInfo.eol -ne $true) {
                        try {
                            $eolDate = [DateTime]::Parse($versionInfo.eol)
                            Write-Host "DEBUG: Date EOL parsée: $($eolDate.ToString('yyyy-MM-dd'))" -ForegroundColor DarkGray
                        } catch {
                            Write-Host "ERREUR: Impossible de parser la date EOL '$($versionInfo.eol)'" -ForegroundColor Yellow
                        }
                    }
                    
                    # PARSING DE LA DATE EOS (End of Support)
                    # La date EOS peut être dans plusieurs champs selon l'API
                    $eosFields = @('support', 'extendedSupport', 'discontinuedAt')
                    foreach ($field in $eosFields) {
                        if ($versionInfo.$field -and $versionInfo.$field -ne $false -and $versionInfo.$field -ne $true) {
                            try {
                                $eosDate = [DateTime]::Parse($versionInfo.$field)
                                Write-Host "DEBUG: Date EOS trouvée dans '$field': $($eosDate.ToString('yyyy-MM-dd'))" -ForegroundColor DarkGray
                                break
                            } catch {
                                Write-Host "ERREUR: Impossible de parser la date EOS depuis '$field': '$($versionInfo.$field)'" -ForegroundColor Yellow
                            }
                        }
                    }
                    
                    # INFO: Beaucoup d'OS n'ont qu'une date EOL, pas de EOS séparée
                    if (-not $eosDate) {
                        Write-Host "INFO: Aucune date EOS séparée trouvée pour $ProductName $Version" -ForegroundColor DarkGray
                    }
                }
                
                # ETAPE 8C: CALCULS DES STATUTS ET DELAIS
                # Détermine si l'OS est déjà EOL/EOS et calcule les jours restants
                $isEOL = if ($isVersionTooGeneric) { $false } else { $eolDate -and $currentDate -gt $eolDate }
                $isEOS = if ($isVersionTooGeneric) { $false } else { $eosDate -and $currentDate -gt $eosDate }
                $daysUntilEOL = if ($isVersionTooGeneric) { $null } else { if ($eolDate) { ($eolDate - $currentDate).Days } else { $null } }
                $daysUntilEOS = if ($isVersionTooGeneric) { $null } else { if ($eosDate) { ($eosDate - $currentDate).Days } else { $null } }
                
                # DEBUG: Affichage des calculs
                Write-Host "DEBUG: Is EOL = $isEOL, Is EOS = $isEOS" -ForegroundColor DarkGray
                if ($daysUntilEOL) { Write-Host "DEBUG: Jours jusqu'à EOL = $daysUntilEOL" -ForegroundColor DarkGray }
                if ($daysUntilEOS) { Write-Host "DEBUG: Jours jusqu'à EOS = $daysUntilEOS" -ForegroundColor DarkGray }
                
                # ETAPE 8D: CREATION DE L'OBJET RESULTAT
                # Structure standardisée pour toutes les réponses d'API
                $result = [PSCustomObject]@{
                    Product = $ProductName                           # Nom du produit API
                    Version = $Version                               # Version normalisée
                    Cycle = $versionInfo.cycle                       # Cycle de l'API (peut différer de Version)
                    EOL_Date = $eolDate                              # Date End of Life (peut être null)
                    EOS_Date = $eosDate                              # Date End of Support (peut être null)
                    Is_EOL = $isEOL                                  # Boolean: true si déjà EOL
                    Is_EOS = $isEOS                                  # Boolean: true si déjà EOS
                    Days_Until_EOL = $daysUntilEOL                   # Nombre de jours jusqu'à EOL (peut être null)
                    Days_Until_EOS = $daysUntilEOS                   # Nombre de jours jusqu'à EOS (peut être null)
                    Latest_Version = $versionInfo.latest             # Dernière version disponible
                    LTS = $versionInfo.lts -eq $true                 # Boolean: true si version LTS
                    Date_Unavailable_Reason = $dateUnavailableReason # Raison si dates non disponibles
                    Raw_Data = $versionInfo                          # Données brutes de l'API (pour debug)
                }
                
                # ETAPE 8E: MISE EN CACHE DU RESULTAT
                # Cache le résultat pour éviter les appels futurs identiques
                $global:ApiCache[$cacheKey] = $result
                
                Write-Host "SUCCESS: Données lifecycle récupérées et mises en cache pour $ProductName $Version" -ForegroundColor Green
                return $result
                
            } else {
                # AUCUNE INFORMATION TROUVEE dans l'API
                Write-Host "ATTENTION: Aucune information lifecycle trouvée pour $ProductName version $Version" -ForegroundColor Yellow
                return $null
            }
            
            # Si on arrive ici, l'appel a réussi, on sort de la boucle de retry
            break
            
        } catch {
            # ETAPE 9: GESTION DES ERREURS AVEC RETRY LOGIC
            $retryCount++
            
            # ANALYSE DU TYPE D'ERREUR pour décider de la stratégie de retry
            $errorMessage = $_.Exception.Message
            
            if ($errorMessage -like "*404*") {
                # ERREUR 404: Produit non supporté par l'API
                Write-Host "ERREUR: Produit '$ProductName' non supporté par l'API endoflife.date" -ForegroundColor Yellow
                return $null  # Pas de retry pour 404, c'est définitif
                
            } elseif ($errorMessage -like "*429*" -or $errorMessage -like "*rate*limit*") {
                # ERREUR 429: Rate limit atteint
                Write-Host "RATE LIMIT: Limite d'API atteinte pour $ProductName (tentative $retryCount/$maxRetries)" -ForegroundColor Yellow
                if ($retryCount -gt $maxRetries) {
                    Write-Host "ECHEC: Nombre maximum de tentatives atteint pour $ProductName après rate limiting" -ForegroundColor Red
                    return $null
                }
                # Continue la boucle pour retry avec exponential backoff
                
            } elseif ($errorMessage -like "*timeout*") {
                # ERREUR TIMEOUT: Connexion trop lente
                Write-Host "TIMEOUT: Délai d'attente dépassé pour $ProductName (tentative $retryCount/$maxRetries)" -ForegroundColor Yellow
                if ($retryCount -gt $maxRetries) {
                    Write-Host "ECHEC: Nombre maximum de tentatives atteint pour $ProductName après timeouts" -ForegroundColor Red
                    return $null
                }
                # Continue la boucle pour retry
                
            } else {
                # AUTRES ERREURS: Erreurs réseau, serveur, etc.
                Write-Host "ERREUR: Problème lors de l'appel API pour $ProductName - $errorMessage" -ForegroundColor Yellow
                if ($retryCount -gt $maxRetries) {
                    Write-Host "ECHEC: Nombre maximum de tentatives atteint pour $ProductName" -ForegroundColor Red
                    return $null
                }
                # Continue la boucle pour retry
            }
        }
    }
    
    # ECHEC COMPLET: Tous les retries ont échoué
    Write-Host "ECHEC FINAL: Impossible de récupérer les données lifecycle pour $ProductName $Version après $maxRetries tentatives" -ForegroundColor Red
    return $null
}

# SECTION 6: FONCTION PRINCIPALE D'ANALYSE DES MACHINES
# =============================================================================
# Fonction maîtresse qui orchestre toute l'analyse du parc informatique
# =============================================================================
#
# OBJECTIF:
# Cette fonction est le cœur du script. Elle lit un fichier Excel d'inventaire,
# analyse chaque machine pour déterminer son statut EOL/EOS, et génère des résultats
# structurés pour tous les rapports.
#
# OPTIMISATIONS CLÉS:
# 1. GROUPEMENT INTELLIGENT: Au lieu d'appeler l'API pour chaque machine,
#    groupe les machines par OS+Version unique et fait un seul appel par groupe.
#    Cela réduit drastiquement le nombre d'appels API (ex: 1000 machines Windows 10 22H2
#    = 1 seul appel API au lieu de 1000).
#
# 2. INCLUSION UNIVERSELLE: Toutes les machines sont incluses dans le résultat,
#    même celles non-analysables, avec un statut approprié et une raison.
#
# 3. TRAITEMENT EN 2 PHASES:
#    - Phase 1: Appels API pour les groupes uniques d'OS+Version
#    - Phase 2: Application rapide des résultats à toutes les machines
#
# FLOW LOGIQUE:
# 1. Lecture et validation du fichier Excel
# 2. Détection des colonnes (OS, nom machine, version)
# 3. Pré-analyse et groupement des machines par OS+Version
# 4. Phase 1: Appels API pour chaque groupe unique
# 5. Phase 2: Application des résultats à toutes les machines
# 6. Calcul des statuts (EOL, EOS, BIENTOT EOL/EOS, VERSION IMPRECISE, NON ANALYSABLE)
# 7. Retour des résultats structurés
#
function Find-EOSMachines-Advanced {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath    # Chemin vers le fichier Excel d'inventaire
    )
    
    try {
        # ETAPE 1: LECTURE ET VALIDATION DU FICHIER EXCEL
        # =================================================================
        Write-Host "ETAPE 1: Lecture du fichier Excel..." -ForegroundColor Green
        
        # Import du fichier Excel en mémoire
        # Utilise le module ImportExcel pour supporter les fichiers .xlsx
        $data = Import-Excel -Path $FilePath
        Write-Host "SUCCESS: Fichier lu avec succès - $($data.Count) machines trouvées" -ForegroundColor Green
        
        # ETAPE 2: VALIDATION DES COLONNES REQUISES
        # =================================================================
        Write-Host "ETAPE 2: Validation de la structure du fichier..." -ForegroundColor Green
        
        # Analyse de la première ligne pour détecter les colonnes disponibles
        $firstRow = $data[0]
        
        # COLONNES OBLIGATOIRES: Ces colonnes doivent être présentes
        $requiredColumns = @("osPlatform", "computerDnsName", "id")
        
        # COLONNES OPTIONNELLES: Pour les versions d'OS (différents noms possibles)
        $optionalColumns = @("version", "Version", "osVersion", "OSVersion")
        
        # Vérification des colonnes obligatoires
        foreach ($column in $requiredColumns) {
            if (-not ($firstRow.PSObject.Properties.Name -contains $column)) {
                Write-Host "ERREUR: Colonne obligatoire '$column' non trouvée!" -ForegroundColor Red
                Write-Host "Colonnes disponibles: $($firstRow.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
                throw "Structure de fichier invalide - colonne '$column' manquante"
            }
        }
        Write-Host "SUCCESS: Toutes les colonnes obligatoires sont présentes" -ForegroundColor Green
        
        # DETECTION DE LA COLONNE VERSION
        # Cherche la première colonne de version disponible (plusieurs noms possibles)
        $versionColumn = $null
        foreach ($column in $optionalColumns) {
            if ($firstRow.PSObject.Properties.Name -contains $column) {
                $versionColumn = $column
                break
            }
        }
        
        if ($versionColumn) {
            Write-Host "SUCCESS: Colonne version détectée: '$versionColumn'" -ForegroundColor Green
        } else {
            Write-Host "INFO: Aucune colonne version explicite trouvée. Extraction depuis les noms d'OS..." -ForegroundColor Yellow
        }
        
        # ETAPE 3: PRE-ANALYSE DU DATASET
        # =================================================================
        Write-Host ""
        Write-Host "ETAPE 3: Pré-analyse du parc informatique..." -ForegroundColor Yellow
        Write-Host "Analyse en cours avec l'API endoflife.date..." -ForegroundColor Yellow
        Write-Host "Durée estimée: quelques minutes selon la diversité des OS..." -ForegroundColor Yellow
        Write-Host "OPTIMISATION: Rate limiting intelligent actif" -ForegroundColor Cyan
        
        # PRE-ANALYSE: Affichage des types d'OS pour informer l'utilisateur
        Write-Host ""
        Write-Host "Distribution des OS dans l'inventaire:" -ForegroundColor Cyan
        $osGroups = $data | Group-Object osPlatform | Sort-Object Count -Descending
        foreach ($group in $osGroups) {
            $percentage = [math]::Round(($group.Count / $data.Count) * 100, 1)
            Write-Host "  - $($group.Name): $($group.Count) machines ($percentage%)" -ForegroundColor White
        }
        sleep -Seconds 5  # Pause pour laisser le temps de lire les infos
        
        # ETAPE 4: OPTIMISATION - GROUPEMENT DES MACHINES
        # =================================================================
        Write-Host ""
        Write-Host "ETAPE 4: Optimisation intelligente des appels API..." -ForegroundColor Cyan
        Write-Host "Groupement des machines par OS+Version pour minimiser les appels..." -ForegroundColor Cyan
        
        # STRUCTURE DE GROUPEMENT:
        # Clé: "ApiProductName-CleanVersion" (ex: "windows-22H2", "ubuntu-20.04")
        # Valeur: Objet avec ApiProduct, Version, liste des Machines, et LifecycleInfo
        $machineGroups = @{}
        
        # PARCOURS DE TOUTES LES MACHINES pour créer les groupes
        foreach ($machine in $data) {
            $osName = $machine.osPlatform
            $osVersion = if ($versionColumn) { $machine.$versionColumn } else { "" }
            
            # Conversion OS → Nom API et normalisation de version
            $apiProductName = Get-ApiProductName -OSName $osName
            $cleanVersion = Get-OSVersion -OSName $osName -Version $osVersion
            
            # CREATION DU GROUPE si OS et version sont analysables
            if ($apiProductName -and $cleanVersion) {
                $groupKey = "$apiProductName-$cleanVersion"
                
                # Initialise le groupe s'il n'existe pas encore
                if (-not $machineGroups.ContainsKey($groupKey)) {
                    $machineGroups[$groupKey] = @{
                        ApiProduct = $apiProductName          # Nom du produit pour l'API
                        Version = $cleanVersion               # Version normalisée
                        Machines = @()                       # Liste des machines de ce groupe
                        LifecycleInfo = $null                # Données lifecycle (rempli en Phase 1)
                    }
                }
                
                # Ajoute la machine au groupe approprié
                $machineGroups[$groupKey].Machines += $machine
            }
            # Note: Les machines non-groupables seront traitées individuellement en Phase 2
        }
        
        # RESULTATS DE L'OPTIMISATION
        $totalMachines = $data.Count
        $groupedMachines = ($machineGroups.Values | ForEach-Object { $_.Machines.Count } | Measure-Object -Sum).Sum
        $uniqueGroups = $machineGroups.Count
        $estimatedApiCalls = $uniqueGroups  # Au lieu de $totalMachines
        $optimization = if ($totalMachines -gt 0) { [math]::Round((1 - ($estimatedApiCalls / $totalMachines)) * 100, 1) } else { 0 }
        
        Write-Host ""
        Write-Host "RESULTATS DE L'OPTIMISATION:" -ForegroundColor Green
        Write-Host "   Total machines: $totalMachines" -ForegroundColor White
        Write-Host "   Machines groupées: $groupedMachines" -ForegroundColor White
        Write-Host "   Groupes uniques d'OS+Version: $uniqueGroups" -ForegroundColor White
        Write-Host "   Appels API estimés: $estimatedApiCalls (au lieu de $totalMachines)" -ForegroundColor Green
        Write-Host "   Optimisation: $optimization% de réduction d'appels API!" -ForegroundColor Green
        
        # ETAPE 5: PHASE 1 - APPELS API POUR LES GROUPES UNIQUES
        # =================================================================
        Write-Host ""
        Write-Host "ETAPE 5: Phase 1 - Récupération des données lifecycle par groupe..." -ForegroundColor Cyan
        
        $groupsProcessed = 0
        $totalGroups = $machineGroups.Count
        
        # PARCOURS DE CHAQUE GROUPE UNIQUE pour appeler l'API
        foreach ($groupKey in $machineGroups.Keys) {
            $groupsProcessed++
            $group = $machineGroups[$groupKey]
            
            # Affichage du progrès avec détails
            Write-Host ""
            Write-Host "ANALYSE Groupe $groupsProcessed/$totalGroups : $($group.ApiProduct) v$($group.Version)" -ForegroundColor White
            Write-Host "   Machines concernées: $($group.Machines.Count)" -ForegroundColor DarkGray
            
            # APPEL API pour ce groupe (un seul appel pour toutes les machines du groupe)
            $group.LifecycleInfo = Get-ProductLifecycle -ProductName $group.ApiProduct -Version $group.Version
            
            # AFFICHAGE DU RESULTAT de l'appel API
            if ($group.LifecycleInfo) {
                $status = if ($group.LifecycleInfo.Is_EOL) { "EOL" } 
                         elseif ($group.LifecycleInfo.Is_EOS) { "EOS" } 
                         elseif ($group.LifecycleInfo.Date_Unavailable_Reason) { "VERSION IMPRECISE" }
                         else { "SUPPORTE" }
                Write-Host "   RESULTAT: $status" -ForegroundColor $(
                    switch ($status) {
                        "EOL" { "Red" }
                        "EOS" { "Red" }
                        "VERSION IMPRECISE" { "Magenta" }
                        default { "Green" }
                    }
                )
            } else {
                Write-Host "   ECHEC de l'appel API" -ForegroundColor Red
            }
            
            # PAUSE INTELLIGENTE entre groupes pour respecter les limites API
            # Ne pause que tous les 5 groupes pour optimiser le temps tout en respectant les limites
            if ($groupsProcessed % 5 -eq 0 -and $groupsProcessed -lt $totalGroups) {
                $pauseDuration = if ($BatchMode) { 10 } else { 0 }  # Plus conservateur en mode batch
                Write-Host "   PAUSE de $pauseDuration sec. entre groupes (protection API)" -ForegroundColor Yellow
                Start-Sleep -Seconds $pauseDuration
            }
        }
        
        # ETAPE 6: PHASE 2 - APPLICATION DES RESULTATS A TOUTES LES MACHINES
        # =================================================================
        Write-Host ""
        Write-Host "ETAPE 6: Phase 2 - Application rapide des résultats à toutes les machines..." -ForegroundColor Cyan
        Write-Host "Cette phase est très rapide car aucun appel API supplémentaire n'est nécessaire" -ForegroundColor DarkGray
        # INITIALISATION DES STRUCTURES DE RESULTATS
        $results = @()                    # Tableau final de tous les résultats (une entrée par machine)
        $processed = 0                    # Compteur de machines traitées
        $totalMachines = $data.Count      # Nombre total de machines à traiter
        
        # BOUCLE PRINCIPALE: TRAITEMENT DE CHAQUE MACHINE INDIVIDUELLE
        # Cette boucle est très rapide car elle n'appelle plus l'API - elle utilise les résultats
        # des groupes déjà récupérés en Phase 1
        foreach ($machine in $data) {
            $processed++
            
            # AFFICHAGE DU PROGRES (tous les 100 machines ou à la fin)
            if ($processed % 100 -eq 0 -or $processed -eq $totalMachines) {
                $percentage = [math]::Round(($processed / $totalMachines) * 100, 1)
                Write-Host "   PROGRESSION: $processed/$totalMachines machines ($percentage%)" -ForegroundColor Cyan
            }
            
            # EXTRACTION DES DONNEES DE BASE de la machine courante
            $osName = $machine.osPlatform                                          # OS de la machine
            $computerName = $machine.computerDnsName                               # Nom de la machine
            $machineId = $machine.id                                               # ID unique de la machine
            $osVersion = if ($versionColumn) { $machine.$versionColumn } else { "" } # Version OS (si disponible)
            
            # INITIALISATION DES VARIABLES DE RESULTAT avec valeurs par défaut
            # Chaque machine commence comme "NON ANALYSABLE" puis est reclassée selon l'analyse
            $status = "NON ANALYSABLE"              # Statut final (EOL, EOS, BIENTOT EOL, etc.)
            $priority = 0                           # Priorité pour le tri (4=EOL, 3=EOS, 2=BIENTOT EOL, etc.)
            $apiProductName = $null                 # Nom du produit API (ex: "windows", "ubuntu")
            $cleanVersion = $null                   # Version normalisée (ex: "22H2", "20.04")
            $lifecycleInfo = $null                  # Données lifecycle de l'API (EOL/EOS dates, etc.)
            $reasonNotAnalyzable = $null            # Raison si la machine n'est pas analysable
            
            # ETAPE 6A: VALIDATION ET ANALYSE DE LA MACHINE COURANTE
            # ========================================================
            # Chaque machine passe par une série de validations pour déterminer si elle peut être analysée
            
            # VALIDATION 1: Vérification que l'OS est défini dans l'inventaire
            if ([string]::IsNullOrEmpty($osName)) {
                # CAS 1: Pas d'OS défini - machine non analysable
                $reasonNotAnalyzable = "OS non défini dans l'inventaire"
                Write-Host "ATTENTION Machine ${computerName}: OS non défini" -ForegroundColor DarkGray
                
            } else {
                # VALIDATION 2: Conversion de l'OS vers le nom API
                $apiProductName = Get-ApiProductName -OSName $osName
                if (-not $apiProductName) {
                    # CAS 2: OS non reconnu par l'API - machine non analysable
                    $reasonNotAnalyzable = "OS non reconnu par l'API: '$osName'"
                    Write-Host "ATTENTION Machine ${computerName}: OS '$osName' non supporté par l'API" -ForegroundColor DarkGray
                    
                } else {
                    # VALIDATION 3: Extraction et nettoyage de la version
                    $cleanVersion = Get-OSVersion -OSName $osName -Version $osVersion
                    if (-not $cleanVersion) {
                        # CAS 3: Version non extractible - machine non analysable
                        $reasonNotAnalyzable = "Version non extractible pour OS '$osName' (version source: '$osVersion')"
                        Write-Host "ATTENTION Machine ${computerName}: Version non extractible pour '$osName'" -ForegroundColor DarkGray
                        
                    } else {
                        # VALIDATION 4: Récupération des données lifecycle depuis les groupes
                        # Utilise les données déjà récupérées en Phase 1 (pas d'appel API ici)
                        $groupKey = "$apiProductName-$cleanVersion"
                        if ($machineGroups.ContainsKey($groupKey)) {
                            $lifecycleInfo = $machineGroups[$groupKey].LifecycleInfo
                            Write-Host "SUCCESS Machine ${computerName}: Données lifecycle trouvées pour '$osName' v$cleanVersion" -ForegroundColor DarkGreen
                        }
                        
                        # VALIDATION 5: Vérification de la réussite de l'appel API
                        if (-not $lifecycleInfo) {
                            # CAS 5: Échec de récupération des données API
                            $reasonNotAnalyzable = "Échec lors de l'appel API pour '$apiProductName' version '$cleanVersion'"
                            Write-Host "ERREUR Machine ${computerName}: Échec API pour '$osName' v$cleanVersion" -ForegroundColor DarkGray
                        }
                    }
                }
            }
            
            # ETAPE 6B: DETERMINATION DU STATUT DE LA MACHINE
            # ================================================
            # Si on a réussi à récupérer les données lifecycle, on détermine le statut exact
            if ($lifecycleInfo) {
                # STATUT PAR DEFAUT: Supporté (sera changé si problème détecté)
                $status = "Supporte"
                $priority = 0  # Priorité 0 = pas de problème
                
                # CAS SPECIAL: Version trop générique
                # Même si on a des données API, la version était insuffisamment précise
                # pour donner des dates EOL/EOS fiables
                if ($lifecycleInfo.Date_Unavailable_Reason) {
                    $status = "VERSION IMPRECISE"
                    $priority = 1  # Priorité faible mais nécessite attention pour clarifier la version
                    Write-Host "VERSION IMPRECISE Machine ${computerName}: Version imprecise ($($lifecycleInfo.Date_Unavailable_Reason))" -ForegroundColor Magenta
                    
                } else {
                    # LOGIQUE DE PRIORITE NORMALE
                    # Ordre de priorité décroissante: EOL > EOS > Bientôt EOL > Bientôt EOS > Supporté
                    
                    # PRIORITE 4 (CRITIQUE): Machine déjà END OF LIFE
                    if ($lifecycleInfo.Is_EOL) {
                        $status = "END OF LIFE"
                        $priority = 4  # Priorité maximum - action urgente requise
                        $daysEOL = if ($lifecycleInfo.Days_Until_EOL) { $lifecycleInfo.Days_Until_EOL } else { "N/A" }
                        Write-Host "CRITIQUE Machine ${computerName}: END OF LIFE (depuis $([math]::Abs($daysEOL)) jours)" -ForegroundColor Red
                        
                    # PRIORITE 3 (CRITIQUE): Machine déjà END OF SUPPORT
                    } elseif ($lifecycleInfo.Is_EOS) {
                        $status = "END OF SUPPORT"
                        $priority = 3  # Priorité élevée - plus de support sécurité
                        $daysEOS = if ($lifecycleInfo.Days_Until_EOS) { $lifecycleInfo.Days_Until_EOS } else { "N/A" }
                        Write-Host "CRITIQUE Machine ${computerName}: END OF SUPPORT (depuis $([math]::Abs($daysEOS)) jours)" -ForegroundColor Red
                        
                    # PRIORITE 2 (ALERTE): Machine bientôt END OF LIFE
                    } elseif ($lifecycleInfo.Days_Until_EOL -and $lifecycleInfo.Days_Until_EOL -lt $WarningDays -and $lifecycleInfo.Days_Until_EOL -gt 0) {
                        $status = "BIENTOT EOL"
                        $priority = 2  # Priorité moyenne - planification requise
                        Write-Host "ALERTE Machine ${computerName}: BIENTOT EOL (dans $($lifecycleInfo.Days_Until_EOL) jours)" -ForegroundColor Yellow
                        
                    # PRIORITE 1 (ATTENTION): Machine bientôt END OF SUPPORT
                    } elseif ($lifecycleInfo.Days_Until_EOS -and $lifecycleInfo.Days_Until_EOS -lt $WarningDays -and $lifecycleInfo.Days_Until_EOS -gt 0) {
                        $status = "BIENTOT EOS"
                        $priority = 1  # Priorité faible - surveillance requise
                        Write-Host "ATTENTION Machine ${computerName}: BIENTOT EOS (dans $($lifecycleInfo.Days_Until_EOS) jours)" -ForegroundColor Yellow
                        
                    # PRIORITE 0 (OK): Machine supportée
                    } else {
                        # Machine supportée - aucune alerte
                        Write-Host "OK Machine ${computerName}: Supporté" -ForegroundColor Green
                    }
                }
            }
            # Note: Si pas de lifecycleInfo, le statut reste "NON ANALYSABLE" (défini plus haut)
            
            # ETAPE 6C: CREATION DE L'OBJET RESULTAT
            # =======================================
            # Chaque machine génère un objet résultat standardisé, qu'elle soit analysable ou non
            # Cette approche garantit que TOUTES les machines apparaissent dans le rapport final
            $result = [PSCustomObject]@{
                # IDENTIFIANTS DE LA MACHINE
                ID = $machineId                                                        # ID unique de la machine
                ComputerName = $computerName                                           # Nom DNS de la machine
                OSPlatform = $osName                                                   # OS tel que dans l'inventaire
                Version = if ($cleanVersion) { $cleanVersion } else { $osVersion }     # Version normalisée ou originale
                
                # STATUT ET PRIORITE
                Status = $status                                                       # Statut final (EOL, EOS, BIENTOT EOL, etc.)
                Priority = $priority                                                   # Priorité pour tri (4=EOL, 3=EOS, 2=BIENTOT EOL, etc.)
                
                # DATES LIFECYCLE (peuvent être null si non analysable)
                EOL_Date = if ($lifecycleInfo) { $lifecycleInfo.EOL_Date } else { $null }         # Date End of Life
                EOS_Date = if ($lifecycleInfo) { $lifecycleInfo.EOS_Date } else { $null }         # Date End of Support
                Days_Until_EOL = if ($lifecycleInfo) { $lifecycleInfo.Days_Until_EOL } else { $null }  # Jours jusqu'à EOL
                Days_Until_EOS = if ($lifecycleInfo) { $lifecycleInfo.Days_Until_EOS } else { $null }  # Jours jusqu'à EOS
                
                # INFORMATIONS COMPLEMENTAIRES
                Latest_Version = if ($lifecycleInfo) { $lifecycleInfo.Latest_Version } else { $null }   # Dernière version disponible
                Is_LTS = if ($lifecycleInfo) { $lifecycleInfo.LTS } else { $null }                      # Est-ce une version LTS
                API_Product = $apiProductName                                                           # Nom du produit API utilisé
                Date_Unavailable_Reason = if ($lifecycleInfo -and $lifecycleInfo.Date_Unavailable_Reason) { $lifecycleInfo.Date_Unavailable_Reason } else { $reasonNotAnalyzable }  # Raison si dates indisponibles
            }
            
            # AJOUT DU RESULTAT au tableau final
            $results += $result
            
            # AFFICHAGE EN TEMPS REEL (optionnel, réduit pour éviter trop d'output)
            # Affiche seulement les machines avec des problèmes, pas toutes les machines supportées
            if ($priority -gt 0 -or $reasonNotAnalyzable) {
                # DETERMINATION DE LA COULEUR D'AFFICHAGE selon le statut
                $statusColor = switch ($status) {
                    "END OF LIFE" { "Red" }
                    "END OF SUPPORT" { "Red" }
                    "BIENTOT EOL" { "Yellow" }
                    "BIENTOT EOS" { "Yellow" }
                    "VERSION IMPRECISE" { "Magenta" }
                    "NON ANALYSABLE" { "Gray" }
                    default { "Green" }
                }
                
                if ($reasonNotAnalyzable) {
                    # Affichage réduit pour les machines non analysables (tous les 50)
                    if ($processed % 50 -eq 0) {
                        Write-Host "NON ANALYSABLE: $computerName - $reasonNotAnalyzable" -ForegroundColor Gray
                    }
                } elseif ($lifecycleInfo -and $lifecycleInfo.Date_Unavailable_Reason) {
                    Write-Host "$status : $computerName - $osName $cleanVersion - $($lifecycleInfo.Date_Unavailable_Reason)" -ForegroundColor $statusColor
                } else {
                    $eosInfo = if ($lifecycleInfo -and $lifecycleInfo.Days_Until_EOS -ne $null) { " (EOS dans $($lifecycleInfo.Days_Until_EOS) jours)" } else { "" }
                    $eolInfo = if ($lifecycleInfo -and $lifecycleInfo.Days_Until_EOL -ne $null) { " (EOL dans $($lifecycleInfo.Days_Until_EOL) jours)" } else { "" }
                    Write-Host "$status : $computerName - $osName $cleanVersion$eolInfo$eosInfo" -ForegroundColor $statusColor
                }
            }
        }
        
        return $results
        
    } catch {
        Write-Host "Erreur lors de l'analyse: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# SECTION 7: VERIFICATION ET INSTALLATION DES MODULES PREREQUIS
# =============================================================================
# Vérification et installation automatique des modules PowerShell nécessaires
# =============================================================================
#
# MODULES REQUIS:
# - ImportExcel: Pour lire les fichiers Excel (.xlsx) d'inventaire
# 
# VERIFICACTIONS:
# - Présence du module ImportExcel
# - Installation automatique si manquant
# - Test de connectivité à l'API endoflife.date
# - Validation du fichier d'entrée
#
Write-Host ""
Write-Host "VERIFICATION DES PREREQUIS TECHNIQUES..." -ForegroundColor Cyan
$currentTime = Get-Date
$elapsedSinceStart = $currentTime - $global:ScriptStartTime
Write-Host "Temps écoulé depuis le démarrage: $([math]::Round($elapsedSinceStart.TotalSeconds, 1)) secondes" -ForegroundColor DarkGray

# ETAPE 1: VERIFICATION DU MODULE IMPORTEXCEL
# Le module ImportExcel est nécessaire pour lire les fichiers .xlsx d'inventaire
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "Module ImportExcel manquant. Installation automatique..." -ForegroundColor Yellow
    try {
        # Configuration du dépôt PowerShell Gallery comme source fiable
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        
        # Installation du module pour l'utilisateur courant (pas besoin de droits admin)
        Install-Module -Name ImportExcel -Force -Scope CurrentUser -SkipPublisherCheck -AllowClobber
        Write-Host "SUCCESS: Module ImportExcel installé avec succès" -ForegroundColor Green
    } catch {
        Write-Host "ERREUR: Impossible d'installer ImportExcel: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Le script tentera de continuer mais pourrait échouer..." -ForegroundColor Yellow
    }
} else {
    Write-Host "Module ImportExcel déjà installé" -ForegroundColor Green
}

# ETAPE 2: IMPORT DU MODULE IMPORTEXCEL
try {
    Import-Module ImportExcel -ErrorAction Stop
    Write-Host "SUCCESS: Module ImportExcel importé et prêt" -ForegroundColor Green
} catch {
    Write-Host "ERREUR: Impossible d'importer ImportExcel: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Le script va essayer de continuer mais la lecture Excel pourrait échouer..." -ForegroundColor Yellow
}

# ETAPE 3: TEST DE CONNECTIVITE A L'API ENDOFLIFE.DATE
# Vérifie que l'API est accessible avant de commencer l'analyse
try {
    Write-Host "Test de connectivité à l'API endoflife.date..." -ForegroundColor Cyan
    $testResponse = Invoke-RestMethod -Uri "$global:ApiBaseUrl/windows.json" -Method Get -TimeoutSec 10
    Write-Host "SUCCESS: API endoflife.date accessible et fonctionnelle" -ForegroundColor Green
} catch {
    Write-Host "ERREUR CRITIQUE: Impossible d'accéder à l'API endoflife.date" -ForegroundColor Red
    Write-Host "Vérifiez votre connexion internet et les proxies/firewalls d'entreprise" -ForegroundColor Yellow
    Write-Host "URL testée: $global:ApiBaseUrl/windows.json" -ForegroundColor Gray
    exit 1
}

# SECTION 8: VALIDATION DU FICHIER D'ENTREE
# =============================================================================
# Vérification de l'existence et de l'accessibilité du fichier Excel
# =============================================================================
Write-Host ""
Write-Host "VALIDATION DU FICHIER D'INVENTAIRE..." -ForegroundColor Cyan
if (!(Test-Path $ExcelPath)) {
    Write-Host "ERREUR CRITIQUE: Fichier Excel non trouvé: $ExcelPath" -ForegroundColor Red
    Write-Host "Vérifiez le chemin et les permissions d'accès au fichier" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "SUCCESS: Fichier Excel trouvé et accessible" -ForegroundColor Green
}

# SECTION 9: DEMARRAGE DE L'EXECUTION PRINCIPALE
# =============================================================================
# Affichage des paramètres et lancement de l'analyse
# =============================================================================
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "EOS/EOL CHECKER AVANCE - KPMG" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "PARAMETRES D'EXECUTION:" -ForegroundColor White
Write-Host "  Fichier analysé: $ExcelPath" -ForegroundColor White
Write-Host "  Seuil d'alerte précoce: $WarningDays jours avant EOL/EOS" -ForegroundColor White
Write-Host "  Cache API: $($UseCache.ToString())" -ForegroundColor White
Write-Host "  Mode Batch (rate limiting renforcé): $($BatchMode.ToString())" -ForegroundColor White
if ($BatchMode) {
    Write-Host "  ATTENTION: Mode Batch activé - traitement plus lent mais plus fiable pour gros inventaires" -ForegroundColor Yellow
}
Write-Host ""

# LANCEMENT DE L'ANALYSE PRINCIPALE
Write-Host "DEMARRAGE DE L'ANALYSE..." -ForegroundColor Green
$analysisStartTime = Get-Date
Write-Host "Heure de début de l'analyse: $($analysisStartTime.ToString('HH:mm:ss'))" -ForegroundColor Green
Write-Host ""

# APPEL DE LA FONCTION PRINCIPALE D'ANALYSE
$results = Find-EOSMachines-Advanced -FilePath $ExcelPath

# CALCUL DU TEMPS D'EXECUTION DE L'ANALYSE
$analysisEndTime = Get-Date
$analysisDuration = $analysisEndTime - $analysisStartTime
Write-Host ""
Write-Host "ANALYSE TERMINEE!" -ForegroundColor Green
Write-Host "Durée de l'analyse: $($analysisDuration.ToString('mm\:ss')) (minutes:secondes)" -ForegroundColor Green
Write-Host "Heure de fin d'analyse: $($analysisEndTime.ToString('HH:mm:ss'))" -ForegroundColor Green

# SECTION 10: TRAITEMENT ET EXPORT DES RESULTATS
# =============================================================================
# Génération des statistiques, rapports Excel et CSV
# =============================================================================
if ($results -and $results.Count -gt 0) {
    
    # Tri par priorite (EOL/EOS en premier)
    $sortedResults = $results | Sort-Object @{Expression="Priority"; Descending=$true}, @{Expression="EOL_Date"; Descending=$false}
    
    # Statistiques
    $eolCount = ($sortedResults | Where-Object { $_.Status -eq "END OF LIFE" }).Count
    $eosCount = ($sortedResults | Where-Object { $_.Status -eq "END OF SUPPORT" }).Count
    $warningEOLCount = ($sortedResults | Where-Object { $_.Status -eq "BIENTOT EOL" }).Count
    $warningEOSCount = ($sortedResults | Where-Object { $_.Status -eq "BIENTOT EOS" }).Count
    $impreciseVersionCount = ($sortedResults | Where-Object { $_.Status -eq "VERSION IMPRECISE" }).Count
    $supportedCount = ($sortedResults | Where-Object { $_.Status -eq "Supporte" }).Count
    $notAnalyzableCount = ($sortedResults | Where-Object { $_.Status -eq "NON ANALYSABLE" }).Count
    
    # Affichage du resume
    Write-Host ""
    Write-Host "RESUME DES RESULTATS:" -ForegroundColor Cyan
    Write-Host "========================" -ForegroundColor Cyan
    Write-Host "Machines END OF LIFE (EOL): $eolCount" -ForegroundColor Red
    Write-Host "Machines END OF SUPPORT (EOS): $eosCount" -ForegroundColor Red
    Write-Host "Machines bientot EOL: $warningEOLCount" -ForegroundColor Yellow
    Write-Host "Machines bientot EOS: $warningEOSCount" -ForegroundColor Yellow
    Write-Host "Machines avec version imprecise: $impreciseVersionCount" -ForegroundColor Magenta
    Write-Host "Machines supportees: $supportedCount" -ForegroundColor Green
    Write-Host "Machines non analysables: $notAnalyzableCount" -ForegroundColor Gray
    Write-Host "Total machines analysees: $($results.Count)" -ForegroundColor White
    Write-Host ""

    sleep -Seconds 5  # Pause pour laisser le temps de lire les infos
    
    # Affichage detaille
    Write-Host "DETAIL DES MACHINES:" -ForegroundColor Cyan
    Write-Host "======================" -ForegroundColor Cyan
    $sortedResults | Format-Table -Property @(
        @{Name="ID"; Expression={$_.ID}; Width=15},
        @{Name="Machine"; Expression={$_.ComputerName}; Width=25},
        @{Name="OS"; Expression={$_.OSPlatform}; Width=20},
        @{Name="Version"; Expression={$_.Version}; Width=15},
        @{Name="Statut"; Expression={$_.Status}; Width=15},
        @{Name="EOL Date"; Expression={if($_.Date_Unavailable_Reason){$_.Date_Unavailable_Reason}elseif($_.EOL_Date){$_.EOL_Date.ToString("yyyy-MM-dd")}else{"N/A"}}; Width=25},
        @{Name="EOS Date"; Expression={if($_.Date_Unavailable_Reason){$_.Date_Unavailable_Reason}elseif($_.EOS_Date){$_.EOS_Date.ToString("yyyy-MM-dd")}else{"N/A"}}; Width=25},
        @{Name="Jours EOL"; Expression={if($_.Date_Unavailable_Reason){"N/A"}elseif($_.Days_Until_EOL -ne $null){$_.Days_Until_EOL}else{"N/A"}}; Width=10},
        @{Name="Jours EOS"; Expression={if($_.Date_Unavailable_Reason){"N/A"}elseif($_.Days_Until_EOS -ne $null){$_.Days_Until_EOS}else{"N/A"}}; Width=10}
    ) -Wrap
    
    # Export des resultats
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    
    # Export Excel detaille
    $outputFile = "EOS_EOL_Analysis_$timestamp.xlsx"
    $sortedResults | Export-Excel -Path $outputFile -WorksheetName "EOS_EOL_Analysis" -AutoSize -BoldTopRow
    Write-Host "Rapport detaille exporte: $outputFile" -ForegroundColor Green
    
    # Export CSV pour traitement
    $csvFile = "EOS_EOL_Analysis_$timestamp.csv"
    $sortedResults | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    Write-Host "Donnees CSV exportees: $csvFile" -ForegroundColor Green
    
    # Resume executif separe avec details par OS et version
    Write-Host "Generation du resume executif detaille..." -ForegroundColor Cyan
    
    # Resume global par statut
    $globalSummary = $sortedResults | Group-Object Status | Select-Object @(
        @{Name="Statut"; Expression={$_.Name}},
        @{Name="Nombre_Total"; Expression={$_.Count}},
        @{Name="Pourcentage"; Expression={[math]::Round(($_.Count / $results.Count) * 100, 1)}}
    ) | Sort-Object @{Expression={
        switch ($_.Statut) {
            "END OF LIFE" { 1 }
            "END OF SUPPORT" { 2 }
            "BIENTOT EOL" { 3 }
            "BIENTOT EOS" { 4 }
            "VERSION IMPRECISE" { 5 }
            "NON ANALYSABLE" { 6 }
            "Supporte" { 7 }
            default { 8 }
        }
    }}
    
    # Details par statut, OS et version
    $detailedSummary = @()
    
    # Pour chaque statut, on cree un detail par OS et version
    $statusList = @("END OF LIFE", "END OF SUPPORT", "BIENTOT EOL", "BIENTOT EOS", "VERSION IMPRECISE", "NON ANALYSABLE", "Supporte")
    
    foreach ($status in $statusList) {
        $statusMachines = $sortedResults | Where-Object { $_.Status -eq $status }
        
        if ($statusMachines.Count -gt 0) {
            # Groupe par OS et Version
            $osVersionGroups = $statusMachines | Group-Object @{Expression={if($_.OSPlatform -and $_.Version){"$($_.OSPlatform) - $($_.Version)"}elseif($_.OSPlatform){"$($_.OSPlatform) - (Version inconnue)"}else{"OS inconnu"}}}
            
            foreach ($group in $osVersionGroups | Sort-Object Name) {
                $detailedSummary += [PSCustomObject]@{
                    Statut = $status
                    OS_Version = $group.Name
                    Nombre = $group.Count
                    Pourcentage_du_Statut = [math]::Round(($group.Count / $statusMachines.Count) * 100, 1)
                    Pourcentage_du_Total = [math]::Round(($group.Count / $results.Count) * 100, 1)
                    # Ajout des dates EOL/EOS si disponibles
                    Date_EOL = if ($group.Group[0].EOL_Date) { $group.Group[0].EOL_Date.ToString("yyyy-MM-dd") } else { "N/A" }
                    Date_EOS = if ($group.Group[0].EOS_Date) { $group.Group[0].EOS_Date.ToString("yyyy-MM-dd") } else { "N/A" }
                    Jours_Jusqu_EOL = if ($group.Group[0].Days_Until_EOL -ne $null) { $group.Group[0].Days_Until_EOL } else { "N/A" }
                    Jours_Jusqu_EOS = if ($group.Group[0].Days_Until_EOS -ne $null) { $group.Group[0].Days_Until_EOS } else { "N/A" }
                    Raison = if ($group.Group[0].Date_Unavailable_Reason) { $group.Group[0].Date_Unavailable_Reason } else { "" }
                }
            }
        }
    }
    
    # Export du resume executif avec plusieurs feuilles
    $summaryFile = "EOS_EOL_Summary_$timestamp.xlsx"
    
    # Feuille 1: Resume global
    $globalSummary | Export-Excel -Path $summaryFile -WorksheetName "Resume_Global" -AutoSize -BoldTopRow
    
    # Feuille 2: Details par OS et Version
    $detailedSummary | Export-Excel -Path $summaryFile -WorksheetName "Details_OS_Version" -AutoSize -BoldTopRow
    
    # Feuille 3: Tableau croise dynamique par statut
    $pivotSummary = @()
    foreach ($status in $statusList) {
        $statusData = $detailedSummary | Where-Object { $_.Statut -eq $status }
        
        # TOUJOURS inclure le statut, même s'il n'y a pas de données (affichera 0)
        $pivotSummary += [PSCustomObject]@{
            Statut = $status
            Nombre_Total = if ($statusData.Count -gt 0) { ($statusData | Measure-Object Nombre -Sum).Sum } else { 0 }
            OS_Versions = if ($statusData.Count -gt 0) { ($statusData | ForEach-Object { "$($_.OS_Version) ($($_.Nombre))" }) -join "; " } else { "Aucune machine" }
            Top_OS_Version = if ($statusData.Count -gt 0) { ($statusData | Sort-Object Nombre -Descending | Select-Object -First 1).OS_Version } else { "N/A" }
            Machines_Top_OS = if ($statusData.Count -gt 0) { ($statusData | Sort-Object Nombre -Descending | Select-Object -First 1).Nombre } else { 0 }
        }
    }
    
    $pivotSummary | Export-Excel -Path $summaryFile -WorksheetName "Resume_par_Statut" -AutoSize -BoldTopRow
    
    # Feuille 4: Machines EOL (End of Life)
    # Filtre toutes les machines qui ont le statut "END OF LIFE"
    $eolMachines = $sortedResults | Where-Object { $_.Status -eq "END OF LIFE" } | Select-Object @(
        @{Name="ComputerName"; Expression={$_.ComputerName}},
        @{Name="ID"; Expression={$_.ID}},
        @{Name="OSPlatform"; Expression={$_.OSPlatform}},
        @{Name="Version"; Expression={$_.Version}},
        @{Name="EOL_Date"; Expression={if($_.EOL_Date){$_.EOL_Date.ToString("yyyy-MM-dd")}else{"N/A"}}},
        @{Name="Jours_depuis_EOL"; Expression={if($_.Days_Until_EOL -ne $null -and $_.Days_Until_EOL -lt 0){[math]::Abs($_.Days_Until_EOL)}else{"N/A"}}}
    ) | Sort-Object ComputerName
    
    if ($eolMachines.Count -gt 0) {
        $eolMachines | Export-Excel -Path $summaryFile -WorksheetName "EOL_Machines" -AutoSize -BoldTopRow
        Write-Host "INFO: $($eolMachines.Count) machines END OF LIFE détectées" -ForegroundColor Red
    } else {
        # Crée un onglet vide avec headers si aucune machine EOL
        @([PSCustomObject]@{
            ComputerName = "Aucune machine EOL détectée"
            ID = ""
            OSPlatform = ""
            Version = ""
            EOL_Date = ""
            Jours_depuis_EOL = ""
        }) | Export-Excel -Path $summaryFile -WorksheetName "EOL_Machines" -AutoSize -BoldTopRow
        Write-Host "INFO: Aucune machine END OF LIFE détectée - onglet créé vide" -ForegroundColor Green
    }
    
    # Feuille 5: Machines EOS (End of Support)
    # Filtre toutes les machines qui ont le statut "END OF SUPPORT"
    $eosMachines = $sortedResults | Where-Object { $_.Status -eq "END OF SUPPORT" } | Select-Object @(
        @{Name="ComputerName"; Expression={$_.ComputerName}},
        @{Name="ID"; Expression={$_.ID}},
        @{Name="OSPlatform"; Expression={$_.OSPlatform}},
        @{Name="Version"; Expression={$_.Version}},
        @{Name="EOS_Date"; Expression={if($_.EOS_Date){$_.EOS_Date.ToString("yyyy-MM-dd")}else{"N/A"}}},
        @{Name="Jours_depuis_EOS"; Expression={if($_.Days_Until_EOS -ne $null -and $_.Days_Until_EOS -lt 0){[math]::Abs($_.Days_Until_EOS)}else{"N/A"}}}
    ) | Sort-Object ComputerName
    
    if ($eosMachines.Count -gt 0) {
        $eosMachines | Export-Excel -Path $summaryFile -WorksheetName "EOS_Machines" -AutoSize -BoldTopRow
        Write-Host "INFO: $($eosMachines.Count) machines END OF SUPPORT détectées" -ForegroundColor Red
    } else {
        # Crée un onglet vide avec headers si aucune machine EOS
        @([PSCustomObject]@{
            ComputerName = "Aucune machine EOS détectée"
            ID = ""
            OSPlatform = ""
            Version = ""
            EOS_Date = ""
            Jours_depuis_EOS = ""
        }) | Export-Excel -Path $summaryFile -WorksheetName "EOS_Machines" -AutoSize -BoldTopRow
        Write-Host "INFO: Aucune machine END OF SUPPORT détectée - onglet créé vide" -ForegroundColor Green
    }
    
    Write-Host "Resume executif detaille exporte: $summaryFile" -ForegroundColor Green
    Write-Host "  - Feuille 'Resume_Global': Vue d'ensemble par statut" -ForegroundColor White
    Write-Host "  - Feuille 'Details_OS_Version': Detail par OS et version pour chaque statut" -ForegroundColor White
    Write-Host "  - Feuille 'Resume_par_Statut': Resume condense avec top OS par statut" -ForegroundColor White
    Write-Host "  - Feuille 'EOL_Machines': Machines End of Life ($($eolMachines.Count) machines)" -ForegroundColor White
    Write-Host "  - Feuille 'EOS_Machines': Machines End of Support ($($eosMachines.Count) machines)" -ForegroundColor White
    
} else {
    Write-Host "Excellente nouvelle! Aucune machine EOL/EOS detectee dans le parc informatique" -ForegroundColor Green
    Write-Host "Toutes les machines analysees sont dans des versions supportees" -ForegroundColor Green
}

Write-Host ""
Write-Host "Analyse complete terminee!" -ForegroundColor Green
Write-Host "Cache API contient $($global:ApiCache.Count) entrees pour les prochaines executions" -ForegroundColor Gray

# =============================================================================
# TIMER FINAL: Calcul du temps total d'exécution du script
# =============================================================================
$global:ScriptEndTime = Get-Date
$global:TotalScriptDuration = $global:ScriptEndTime - $global:ScriptStartTime

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "SCRIPT EOS/EOL CHECKER - TERMINE" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Heure de fin: $($global:ScriptEndTime.ToString('dd/MM/yyyy HH:mm:ss'))" -ForegroundColor Green
Write-Host "DUREE TOTALE D'EXECUTION: $($global:TotalScriptDuration.ToString('mm\:ss')) (minutes:secondes)" -ForegroundColor Yellow
if ($global:TotalScriptDuration.TotalMinutes -ge 1) {
    Write-Host "                          $([math]::Round($global:TotalScriptDuration.TotalMinutes, 2)) minutes" -ForegroundColor Yellow
}
Write-Host "                          $([math]::Round($global:TotalScriptDuration.TotalSeconds, 1)) secondes" -ForegroundColor Yellow
Write-Host ""

# =============================================================================
# FIN DU SCRIPT YOUPI!
# =============================================================================
