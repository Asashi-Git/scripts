#!/bin/bash

# ========================================================================
# Script: auto-patching-manager.sh
# Description: Orchestrateur principal pour la gestion automatisée des mises à jour
# Usage: ./auto-patching-manager.sh [setup|download|install|backup|rollback|help]
# Author: Decarnelle Samuel
# Version: 1.0
# ========================================================================
# Script orchestrateur qui gère l'exécution des trois autres scripts
# (download.sh, install.sh, rollback.sh) avec interface TUI et support
# d'automatisation via arguments en ligne de commande.
# ========================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Configuration globale
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/log"
PACKAGE_LIST_DIR="${SCRIPT_DIR}/package-list"
PACKAGE_LIST_OLD_DIR="${SCRIPT_DIR}/package-list-old"
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="${LOG_DIR}/manager_${TIMESTAMP}.log"

# Scripts gérés
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
DOWNLOAD_SCRIPT="${SCRIPTS_DIR}/download.sh"
INSTALL_SCRIPT="${SCRIPTS_DIR}/install.sh"
ROLLBACK_SCRIPT="${SCRIPTS_DIR}/rollback.sh"

# Version du système
VERSION="1.0"
SYSTEM_NAME="Auto-Patching Manager"

# ========================================================================
# FONCTION: Vérification des privilèges root
# ========================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERREUR: Ce script doit être exécuté en tant que root (sudo)." >&2
        echo "Usage: sudo $0 [setup|download|install|backup|rollback|help]" >&2
        exit 1
    fi
}

# ========================================================================
# FONCTION: Affichage de l'aide complète
# ========================================================================
show_help() {
    cat << EOF
========================================
$SYSTEM_NAME v$VERSION
========================================

DESCRIPTION:
    Orchestrateur principal pour la gestion automatisée et sécurisée 
    des mises à jour logicielles sur distributions Linux.

USAGE:
    sudo $0 [COMMANDE] [OPTIONS]

COMMANDES:
    setup           Initialise l'environnement (répertoires et permissions)
    download        Télécharge la liste des mises à jour disponibles
    install         Installe les mises à jour précédemment téléchargées
    backup          Gère les sauvegardes système (création/restauration)
    rollback        Accès au système de rollback complet
    status          Affiche l'état du système de patching
    help            Affiche cette aide
    
    [aucune]        Lance l'interface TUI interactive

OPTIONS POUR INSTALL:
    --backup        Force la création d'une sauvegarde avant installation
    --restore NAME  Restaure une sauvegarde spécifique

OPTIONS POUR BACKUP/ROLLBACK:
    create [NAME]   Crée une nouvelle sauvegarde
    restore NAME    Restaure une sauvegarde
    list            Liste les sauvegardes disponibles
    delete NAME     Supprime une sauvegarde

EXEMPLES:
    sudo $0                           # Interface TUI interactive
    sudo $0 setup                     # Configuration initiale
    sudo $0 download                  # Téléchargement des mises à jour
    sudo $0 install --backup          # Installation avec sauvegarde
    sudo $0 backup create mysave      # Création d'une sauvegarde nommée
    sudo $0 rollback restore mysave   # Restauration d'une sauvegarde
    sudo $0 status                    # État du système

AUTOMATISATION:
    Ce script peut être utilisé dans des tâches automatisées (cron, systemd)
    en utilisant les commandes directes sans interface TUI.

RÉPERTOIRES:
    package-list/        Listes des paquets à mettre à jour
    package-list-old/    Archive des anciennes listes
    backups/             Sauvegardes système
    log/                 Journaux d'exécution

DISTRIBUTIONS SUPPORTÉES:
    - Debian/Ubuntu/Linux Mint (APT)
    - Fedora/RHEL/CentOS/Rocky/AlmaLinux (DNF/YUM)
    - Arch/Manjaro/EndeavourOS (Pacman)
    - openSUSE (Zypper)

========================================
EOF
}

# ========================================================================
# FONCTION: Logging avec niveaux de gravité
# ========================================================================
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Création du répertoire de log si nécessaire
    [[ ! -d "$LOG_DIR" ]] && mkdir -p "$LOG_DIR"
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    # Affichage coloré selon le niveau
    case "$level" in
        "ERROR")   echo -e "\033[31m[$timestamp] [ERROR] $message\033[0m" ;;
        "WARNING") echo -e "\033[33m[$timestamp] [WARNING] $message\033[0m" ;;
        "SUCCESS") echo -e "\033[32m[$timestamp] [SUCCESS] $message\033[0m" ;;
        "INFO")    echo -e "\033[36m[$timestamp] [INFO] $message\033[0m" ;;
        "SYSTEM")  echo -e "\033[35m[$timestamp] [SYSTEM] $message\033[0m" ;;
    esac
}

# ========================================================================
# FONCTION: Bannière d'accueil
# ========================================================================
show_banner() {
    echo ""
    echo "=========================================="
    echo "    $SYSTEM_NAME v$VERSION"
    echo "=========================================="
    echo "  Gestion avancée des mises à jour Linux"
    echo "  Support multi-distributions"
    echo "  Sauvegarde et rollback intégrés"
    echo "=========================================="
    echo ""
}

# ========================================================================
# FONCTION: Configuration initiale du système (setup)
# ========================================================================
setup_environment() {
    log_message "SYSTEM" "Initialisation de l'environnement Auto-Patching Manager"
    
    echo "=========================================="
    echo "CONFIGURATION INITIALE"
    echo "=========================================="
    
    # Création de tous les répertoires nécessaires
    local directories=(
        "$LOG_DIR"
        "$PACKAGE_LIST_DIR" 
        "$PACKAGE_LIST_OLD_DIR"
        "$BACKUP_DIR"
        "$SCRIPTS_DIR"
    )
    
    log_message "INFO" "Création des répertoires de travail..."
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 755 "$dir"
            log_message "SUCCESS" "Répertoire créé: $dir"
        else
            log_message "INFO" "Répertoire existant: $dir"
        fi
    done
    
    # Vérification et correction des permissions des scripts
    log_message "INFO" "Vérification des permissions des scripts..."
    local scripts=("$DOWNLOAD_SCRIPT" "$INSTALL_SCRIPT" "$ROLLBACK_SCRIPT")
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            chmod +x "$script"
            log_message "SUCCESS" "Script rendu exécutable: $(basename "$script")"
        else
            log_message "WARNING" "Script manquant: $(basename "$script")"
        fi
    done
    
    # Création d'un fichier de configuration
    local config_file="${SCRIPT_DIR}/auto-patching.conf"
    if [[ ! -f "$config_file" ]]; then
        cat > "$config_file" << EOF
# Configuration Auto-Patching Manager
# Généré le: $(date)

# Paramètres généraux
SYSTEM_VERSION=$VERSION
SETUP_DATE=$(date)
SETUP_USER=$USER
SETUP_HOSTNAME=$(hostname)

# Répertoires
LOG_DIR=$LOG_DIR
PACKAGE_LIST_DIR=$PACKAGE_LIST_DIR
BACKUP_DIR=$BACKUP_DIR

# Options par défaut
AUTO_BACKUP_BEFORE_INSTALL=true
KEEP_OLD_PACKAGES=true
MAX_LOG_FILES=30

# Sécurité
REQUIRE_ROOT=true
VERIFY_CHECKSUMS=true
EOF
        chmod 644 "$config_file"
        log_message "SUCCESS" "Fichier de configuration créé: auto-patching.conf"
    fi
    
    # Vérification de la distribution système
    log_message "INFO" "Détection de la distribution système..."
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        log_message "SUCCESS" "Distribution détectée: $NAME ($VERSION_ID)"
    else
        log_message "WARNING" "Impossible de détecter la distribution"
    fi
    
    # Test de connectivité réseau
    log_message "INFO" "Test de connectivité réseau..."
    if ping -c 1 8.8.8.8 &>/dev/null; then
        log_message "SUCCESS" "Connectivité réseau disponible"
    else
        log_message "WARNING" "Connectivité réseau limitée"
    fi
    
    echo "=========================================="
    echo "CONFIGURATION TERMINÉE"
    echo "=========================================="
    echo "Répertoires créés et permissions configurées."
    echo "Le système est prêt à l'utilisation."
    echo ""
    echo "Étapes suivantes recommandées:"
    echo "1. sudo $0 download    # Télécharger les mises à jour"
    echo "2. sudo $0 install     # Installer les mises à jour"
    echo "=========================================="
    
    log_message "SYSTEM" "Configuration initiale terminée avec succès"
    return 0
}

# ========================================================================
# FONCTION: Affichage de l'état du système
# ========================================================================
show_status() {
    log_message "INFO" "Génération du rapport d'état système"
    
    echo "=========================================="
    echo "ÉTAT DU SYSTÈME AUTO-PATCHING"
    echo "=========================================="
    
    # Informations générales
    echo "Date/Heure: $(date)"
    echo "Hostname: $(hostname)"
    echo "Version: $VERSION"
    echo ""
    
    # État des répertoires
    echo "RÉPERTOIRES:"
    local dirs=("$LOG_DIR" "$PACKAGE_LIST_DIR" "$PACKAGE_LIST_OLD_DIR" "$BACKUP_DIR")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "N/A")
            local files=$(find "$dir" -type f 2>/dev/null | wc -l || echo "0")
            printf "  %-20s: ✓ Existe (%s, %s fichiers)\n" "$(basename "$dir")" "$size" "$files"
        else
            printf "  %-20s: ✗ Manquant\n" "$(basename "$dir")"
        fi
    done
    echo ""
    
    # État des scripts
    echo "SCRIPTS:"
    local scripts=("$DOWNLOAD_SCRIPT" "$INSTALL_SCRIPT" "$ROLLBACK_SCRIPT")
    for script in "${scripts[@]}"; do
        local name=$(basename "$script")
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                printf "  %-20s: ✓ Disponible et exécutable\n" "$name"
            else
                printf "  %-20s: ⚠ Disponible mais non exécutable\n" "$name"
            fi
        else
            printf "  %-20s: ✗ Manquant\n" "$name"
        fi
    done
    echo ""
    
    # Dernières listes de paquets
    echo "LISTES DE PAQUETS:"
    if [[ -d "$PACKAGE_LIST_DIR" ]]; then
        local latest=$(find "$PACKAGE_LIST_DIR" -name "packages_*.txt" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")
        if [[ -n "$latest" ]]; then
            local date=$(stat -c %y "$latest" | cut -d' ' -f1)
            local count=$(grep -c "^[^#]" "$latest" 2>/dev/null || echo "0")
            echo "  Dernière liste: $(basename "$latest")"
            echo "  Date: $date"
            echo "  Paquets: $count"
        else
            echo "  Aucune liste de paquets trouvée"
        fi
    else
        echo "  Répertoire des listes manquant"
    fi
    echo ""
    
    # Sauvegardes disponibles
    echo "SAUVEGARDES:"
    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_count=$(find "$BACKUP_DIR" -name "*.backup" -type f 2>/dev/null | wc -l || echo "0")
        if [[ $backup_count -gt 0 ]]; then
            echo "  Nombre de sauvegardes: $backup_count"
            local latest_backup=$(find "$BACKUP_DIR" -name "*.backup" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
            if [[ -n "$latest_backup" ]]; then
                local backup_date=$(stat -c %y "$latest_backup" | cut -d' ' -f1)
                echo "  Dernière sauvegarde: $(basename "$latest_backup" .backup)"
                echo "  Date: $backup_date"
            fi
        else
            echo "  Aucune sauvegarde trouvée"
        fi
    else
        echo "  Répertoire des sauvegardes manquant"
    fi
    echo ""
    
    # Logs récents
    echo "LOGS:"
    if [[ -d "$LOG_DIR" ]]; then
        local log_count=$(find "$LOG_DIR" -name "*.log" -type f 2>/dev/null | wc -l || echo "0")
        echo "  Nombre de fichiers de log: $log_count"
        if [[ $log_count -gt 0 ]]; then
            local latest_log=$(find "$LOG_DIR" -name "*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
            if [[ -n "$latest_log" ]]; then
                local log_date=$(stat -c %y "$latest_log" | cut -d' ' -f1)
                echo "  Dernier log: $(basename "$latest_log")"
                echo "  Date: $log_date"
            fi
        fi
    else
        echo "  Répertoire des logs manquant"
    fi
    
    echo "=========================================="
    
    return 0
}

# ========================================================================
# FONCTION: Exécution sécurisée des scripts
# ========================================================================
execute_script() {
    local script="$1"
    shift
    local script_name=$(basename "$script")
    
    log_message "SYSTEM" "Exécution de $script_name avec arguments: $*"
    
    # Vérification de l'existence du script
    if [[ ! -f "$script" ]]; then
        log_message "ERROR" "Script introuvable: $script_name"
        echo "ERREUR: Le script $script_name est manquant."
        echo "Exécutez 'sudo $0 setup' pour configurer l'environnement."
        return 1
    fi
    
    # Vérification des permissions
    if [[ ! -x "$script" ]]; then
        log_message "WARNING" "Script non exécutable, correction des permissions: $script_name"
        chmod +x "$script"
    fi
    
    # Exécution avec gestion d'erreur
    echo "=========================================="
    echo "EXÉCUTION: $script_name"
    echo "=========================================="
    
    if "$script" "$@"; then
        log_message "SUCCESS" "Exécution réussie de $script_name"
        return 0
    else
        local exit_code=$?
        log_message "ERROR" "Échec de l'exécution de $script_name (code: $exit_code)"
        return $exit_code
    fi
}

# ========================================================================
# FONCTION: Interface TUI interactive
# ========================================================================
interactive_menu() {
    while true; do
        show_banner
        
        echo "MENU PRINCIPAL:"
        echo "1. Télécharger les mises à jour (download.sh)"
        echo "2. Installer les mises à jour (install.sh)"  
        echo "3. Gestion des sauvegardes (rollback.sh)"
        echo "4. Afficher l'état du système"
        echo "5. Configuration initiale (setup)"
        echo "6. Afficher l'aide"
        echo "7. Quitter"
        echo ""
        
        read -p "Choisissez une option (1-7): " choice
        
        case $choice in
            1)
                echo ""
                log_message "INFO" "Lancement du téléchargement via interface TUI"
                execute_script "$DOWNLOAD_SCRIPT"
                ;;
            2)
                echo ""
                echo "Options d'installation:"
                echo "1. Installation normale (avec confirmation sauvegarde)"
                echo "2. Installation avec sauvegarde automatique"
                echo "3. Retour au menu principal"
                echo ""
                read -p "Choisissez (1-3): " install_choice
                
                case $install_choice in
                    1)
                        log_message "INFO" "Installation normale via interface TUI"
                        execute_script "$INSTALL_SCRIPT"
                        ;;
                    2)
                        log_message "INFO" "Installation avec sauvegarde automatique via interface TUI"
                        execute_script "$INSTALL_SCRIPT" --backup
                        ;;
                    3)
                        continue
                        ;;
                    *)
                        echo "Option invalide."
                        ;;
                esac
                ;;
            3)
                echo ""
                log_message "INFO" "Lancement de la gestion des sauvegardes via interface TUI"
                execute_script "$ROLLBACK_SCRIPT" interactive
                ;;
            4)
                echo ""
                show_status
                ;;
            5)
                echo ""
                setup_environment
                ;;
            6)
                show_help
                ;;
            7)
                log_message "INFO" "Sortie de l'interface TUI"
                echo "Au revoir!"
                exit 0
                ;;
            *)
                echo "Option invalide. Veuillez choisir entre 1 et 7."
                ;;
        esac
        
        echo ""
        read -p "Appuyez sur Entrée pour continuer..."
    done
}

# ========================================================================
# FONCTION: Gestion des arguments de ligne de commande
# ========================================================================
parse_arguments() {
    case "${1:-interactive}" in
        "setup")
            setup_environment
            exit $?
            ;;
        "download")
            execute_script "$DOWNLOAD_SCRIPT"
            exit $?
            ;;
        "install")
            shift
            execute_script "$INSTALL_SCRIPT" "$@"
            exit $?
            ;;
        "backup")
            shift
            execute_script "$ROLLBACK_SCRIPT" "$@"
            exit $?
            ;;
        "rollback")
            shift
            execute_script "$ROLLBACK_SCRIPT" "$@"
            exit $?
            ;;
        "status")
            show_status
            exit $?
            ;;
        "help"|"--help"|"-h")
            show_help
            exit 0
            ;;
        "interactive"|"")
            interactive_menu
            ;;
        *)
            log_message "ERROR" "Commande inconnue: ${1:-}"
            echo "ERREUR: Commande inconnue '${1:-}'"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# ========================================================================
# FONCTION: Nettoyage et maintenance automatique
# ========================================================================
maintenance() {
    log_message "INFO" "Exécution de la maintenance automatique"
    
    # Nettoyage des logs anciens (garde les 30 derniers)
    if [[ -d "$LOG_DIR" ]]; then
        local log_count=$(find "$LOG_DIR" -name "*.log" -type f | wc -l)
        if [[ $log_count -gt 30 ]]; then
            find "$LOG_DIR" -name "*.log" -type f -printf '%T@ %p\n' | sort -n | head -n -30 | cut -d' ' -f2- | xargs rm -f
            log_message "SUCCESS" "Logs anciens nettoyés (gardé les 30 plus récents)"
        fi
    fi
    
    # Vérification de l'espace disque
    local disk_usage=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        log_message "WARNING" "Espace disque faible: ${disk_usage}% utilisé"
    fi
}

# ========================================================================
# FONCTION: Gestion des signaux
# ========================================================================
cleanup_on_exit() {
    log_message "INFO" "Arrêt propre du script manager"
    exit 0
}

# ========================================================================
# FONCTION PRINCIPALE
# ========================================================================
main() {
    # Gestion des signaux
    trap cleanup_on_exit INT TERM EXIT
    
    # Vérifications préliminaires
    check_root
    
    # Initialisation du log
    log_message "SYSTEM" "Démarrage de $SYSTEM_NAME v$VERSION"
    log_message "INFO" "Timestamp: $TIMESTAMP"
    log_message "INFO" "Arguments: $*"
    log_message "INFO" "Utilisateur: $USER"
    log_message "INFO" "Hostname: $(hostname)"
    
    # Maintenance automatique
    maintenance
    
    # Parsing et exécution
    parse_arguments "$@"
}

# Exécution du script principal
main "$@"
