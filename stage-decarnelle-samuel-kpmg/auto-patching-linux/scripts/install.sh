#!/bin/bash

# ========================================================================
# Script: install.sh
# Description: Installe les paquets préalablement téléchargés par download.sh
# Usage: ./install.sh [--backup|--restore <backup_name>]
# Author: Decarnelle Samuel
# Version: 1.0
# ========================================================================
# Ce script installe uniquement les paquets listés par download.sh avec
# possibilité de sauvegarde automatique et de restauration d'état.
# Toute installation est précédée d'une sauvegarde sécurisée.
# ========================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Configuration globale
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGE_LIST_DIR="${BASE_DIR}/package-list"
BACKUP_DIR="${BASE_DIR}/backups"
LOG_DIR="${BASE_DIR}/log"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="${LOG_DIR}/install_${TIMESTAMP}.log"

# Variables globales pour la distribution
DISTRO=""
PACKAGE_MANAGER=""
INSTALL_CMD=""
LIST_INSTALLED_CMD=""
BACKUP_CMD=""
RESTORE_CMD=""

# ========================================================================
# FONCTION: Vérification des privilèges root
# ========================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERREUR: Ce script doit être exécuté en tant que root (sudo)." >&2
        echo "Usage: sudo $0 [--backup|--restore <backup_name>]" >&2
        exit 1
    fi
}

# ========================================================================
# FONCTION: Affichage de l'aide
# ========================================================================
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --backup        Créer une sauvegarde avant installation
    --restore NAME  Restaurer une sauvegarde spécifique
    --help          Afficher cette aide

EXEMPLES:
    sudo $0                    # Installation avec prompt pour sauvegarde
    sudo $0 --backup           # Installation avec sauvegarde automatique
    sudo $0 --restore backup1  # Restaurer la sauvegarde 'backup1'

EOF
}

# ========================================================================
# FONCTION: Logging avec niveaux de gravité
# ========================================================================
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    # Affichage coloré selon le niveau
    case "$level" in
        "ERROR")   echo -e "\033[31m[$timestamp] [ERROR] $message\033[0m" ;;
        "WARNING") echo -e "\033[33m[$timestamp] [WARNING] $message\033[0m" ;;
        "SUCCESS") echo -e "\033[32m[$timestamp] [SUCCESS] $message\033[0m" ;;
        "INFO")    echo -e "\033[36m[$timestamp] [INFO] $message\033[0m" ;;
    esac
}

# ========================================================================
# FONCTION: Détection automatique de la distribution et du gestionnaire de paquets
# ========================================================================
detect_distribution() {
    local distro=""
    local package_manager=""
    
    log_message "INFO" "Détection de la distribution en cours..."
    
    # Détection via /etc/os-release (méthode principale)
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            "ubuntu"|"debian"|"linuxmint"|"pop")
                distro="debian"
                package_manager="apt"
                INSTALL_CMD="apt install -y"
                LIST_INSTALLED_CMD="dpkg-query -W -f='\${Package} \${Version} \${Status}\n'"
                BACKUP_CMD="dpkg --get-selections"
                RESTORE_CMD="dpkg --set-selections"
                ;;
            "fedora"|"rhel"|"centos"|"rocky"|"almalinux")
                if command -v dnf >/dev/null 2>&1; then
                    distro="fedora"
                    package_manager="dnf"
                    INSTALL_CMD="dnf install -y"
                    LIST_INSTALLED_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'"
                    BACKUP_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'"
                    RESTORE_CMD="dnf install -y"
                elif command -v yum >/dev/null 2>&1; then
                    distro="rhel"
                    package_manager="yum"
                    INSTALL_CMD="yum install -y"
                    LIST_INSTALLED_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'"
                    BACKUP_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'"
                    RESTORE_CMD="yum install -y"
                fi
                ;;
            "arch"|"manjaro"|"endeavouros")
                distro="arch"
                package_manager="pacman"
                INSTALL_CMD="pacman -S --noconfirm"
                LIST_INSTALLED_CMD="pacman -Q"
                BACKUP_CMD="pacman -Qq"
                RESTORE_CMD="pacman -S --noconfirm"
                ;;
            "opensuse"|"opensuse-leap"|"opensuse-tumbleweed")
                distro="opensuse"
                package_manager="zypper"
                INSTALL_CMD="zypper install -y"
                LIST_INSTALLED_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'"
                BACKUP_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'"
                RESTORE_CMD="zypper install -y"
                ;;
        esac
    fi
    
    # Vérification de détection alternative si échec
    if [[ -z "$package_manager" ]]; then
        if command -v apt >/dev/null 2>&1; then
            distro="debian"
            package_manager="apt"
            INSTALL_CMD="apt install -y"
            LIST_INSTALLED_CMD="dpkg-query -W -f='\${Package} \${Version} \${Status}\n'"
            BACKUP_CMD="dpkg --get-selections"
            RESTORE_CMD="dpkg --set-selections"
        elif command -v dnf >/dev/null 2>&1; then
            distro="fedora"
            package_manager="dnf"
            INSTALL_CMD="dnf install -y"
            LIST_INSTALLED_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'"
            BACKUP_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'"
            RESTORE_CMD="dnf install -y"
        elif command -v yum >/dev/null 2>&1; then
            distro="rhel"
            package_manager="yum"
            INSTALL_CMD="yum install -y"
            LIST_INSTALLED_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'"
            BACKUP_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'"
            RESTORE_CMD="yum install -y"
        elif command -v pacman >/dev/null 2>&1; then
            distro="arch"
            package_manager="pacman"
            INSTALL_CMD="pacman -S --noconfirm"
            LIST_INSTALLED_CMD="pacman -Q"
            BACKUP_CMD="pacman -Qq"
            RESTORE_CMD="pacman -S --noconfirm"
        elif command -v zypper >/dev/null 2>&1; then
            distro="opensuse"
            package_manager="zypper"
            INSTALL_CMD="zypper install -y"
            LIST_INSTALLED_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'"
            BACKUP_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'"
            RESTORE_CMD="zypper install -y"
        fi
    fi
    
    # Vérification finale
    if [[ -z "$package_manager" ]]; then
        log_message "ERROR" "Distribution non supportée ou gestionnaire de paquets introuvable"
        log_message "ERROR" "Distributions supportées: Debian/Ubuntu, Fedora/RHEL/CentOS, Arch, openSUSE"
        exit 2
    fi
    
    log_message "SUCCESS" "Distribution détectée: $distro avec gestionnaire $package_manager"
    
    # Export des variables globales
    export DISTRO="$distro"
    export PACKAGE_MANAGER="$package_manager"
}

# ========================================================================
# FONCTION: Création des répertoires avec droits appropriés
# ========================================================================
create_directories() {
    log_message "INFO" "Vérification des répertoires de travail..."
    
    for dir in "$BACKUP_DIR" "$LOG_DIR"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 755 "$dir"
            log_message "SUCCESS" "Répertoire créé: $dir"
        fi
    done
    
    # Vérification de l'existence du répertoire des listes de paquets
    if [[ ! -d "$PACKAGE_LIST_DIR" ]]; then
        log_message "ERROR" "Répertoire des listes de paquets introuvable: $PACKAGE_LIST_DIR"
        log_message "ERROR" "Veuillez exécuter download.sh en premier"
        exit 3
    fi
}

# ========================================================================
# FONCTION: Recherche du fichier de liste de paquets le plus récent
# ========================================================================
find_latest_package_list() {
    local latest_file=""
    
    log_message "INFO" "Recherche du fichier de liste de paquets le plus récent..."
    
    # Recherche du fichier le plus récent
    latest_file=$(find "$PACKAGE_LIST_DIR" -name "packages_*.txt" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -z "$latest_file" ]] || [[ ! -f "$latest_file" ]]; then
        log_message "ERROR" "Aucun fichier de liste de paquets trouvé dans $PACKAGE_LIST_DIR"
        log_message "ERROR" "Veuillez exécuter download.sh en premier"
        exit 4
    fi
    
    log_message "SUCCESS" "Fichier de liste trouvé: $(basename "$latest_file")"
    echo "$latest_file"
}

# ========================================================================
# FONCTION: Création d'une sauvegarde complète du système
# ========================================================================
create_backup() {
    local backup_name="${1:-backup_${TIMESTAMP}}"
    local backup_file="${BACKUP_DIR}/${backup_name}.backup"
    local metadata_file="${BACKUP_DIR}/${backup_name}.metadata"
    
    log_message "INFO" "Création de la sauvegarde: $backup_name"
    
    # Création du fichier de sauvegarde principal
    case "$PACKAGE_MANAGER" in
        "apt")
            # Sauvegarde des sélections de paquets Debian/Ubuntu
            dpkg --get-selections > "$backup_file"
            dpkg-query -W -f='${Package} ${Version} ${Status}\n' > "${backup_file}.detailed"
            ;;
        "dnf"|"yum"|"zypper")
            # Sauvegarde des paquets RPM
            eval "$BACKUP_CMD" > "$backup_file"
            eval "$LIST_INSTALLED_CMD" > "${backup_file}.detailed"
            ;;
        "pacman")
            # Sauvegarde des paquets Arch
            pacman -Qq > "$backup_file"
            pacman -Q > "${backup_file}.detailed"
            ;;
    esac
    
    # Création des métadonnées
    cat > "$metadata_file" << EOF
# Métadonnées de sauvegarde
BACKUP_NAME=$backup_name
TIMESTAMP=$TIMESTAMP
DISTRO=$DISTRO
PACKAGE_MANAGER=$PACKAGE_MANAGER
CREATION_DATE=$(date)
HOSTNAME=$(hostname)
KERNEL_VERSION=$(uname -r)
BACKUP_SIZE=$(wc -l < "$backup_file")
EOF
    
    # Calcul des checksums
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$backup_file" > "${backup_file}.sha256"
        log_message "SUCCESS" "Checksum SHA256 généré"
    fi
    
    chmod 644 "$backup_file" "$metadata_file" "${backup_file}.detailed"
    
    log_message "SUCCESS" "Sauvegarde créée: $backup_name ($(wc -l < "$backup_file") paquets)"
    return 0
}

# ========================================================================
# FONCTION: Liste des sauvegardes disponibles
# ========================================================================
list_backups() {
    log_message "INFO" "Sauvegardes disponibles:"
    
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR"/*.backup 2>/dev/null)" ]]; then
        log_message "WARNING" "Aucune sauvegarde trouvée"
        return 1
    fi
    
    echo "========================================"
    printf "%-20s %-15s %-10s\n" "NOM" "DATE" "PAQUETS"
    echo "========================================"
    
    for backup in "$BACKUP_DIR"/*.backup; do
        if [[ -f "$backup" ]]; then
            local name=$(basename "$backup" .backup)
            local metadata="${BACKUP_DIR}/${name}.metadata"
            local date="N/A"
            local count="N/A"
            
            if [[ -f "$metadata" ]]; then
                date=$(grep "CREATION_DATE=" "$metadata" | cut -d'=' -f2- | cut -d' ' -f1)
                count=$(grep "BACKUP_SIZE=" "$metadata" | cut -d'=' -f2)
            else
                count=$(wc -l < "$backup")
            fi
            
            printf "%-20s %-15s %-10s\n" "$name" "$date" "$count"
        fi
    done
    echo "========================================"
}

# ========================================================================
# FONCTION: Restauration d'une sauvegarde
# ========================================================================
restore_backup() {
    local backup_name="$1"
    local backup_file="${BACKUP_DIR}/${backup_name}.backup"
    local metadata_file="${BACKUP_DIR}/${backup_name}.metadata"
    
    log_message "INFO" "Restauration de la sauvegarde: $backup_name"
    
    # Vérification de l'existence de la sauvegarde
    if [[ ! -f "$backup_file" ]]; then
        log_message "ERROR" "Sauvegarde introuvable: $backup_name"
        return 1
    fi
    
    # Vérification de l'intégrité si checksum disponible
    if [[ -f "${backup_file}.sha256" ]]; then
        if sha256sum -c "${backup_file}.sha256" &>/dev/null; then
            log_message "SUCCESS" "Vérification d'intégrité réussie"
        else
            log_message "ERROR" "Échec de la vérification d'intégrité"
            return 1
        fi
    fi
    
    # Création d'une sauvegarde de sécurité avant restauration
    create_backup "pre_restore_${TIMESTAMP}"
    
    # Restauration selon le gestionnaire de paquets
    case "$PACKAGE_MANAGER" in
        "apt")
            log_message "INFO" "Restauration des sélections de paquets..."
            if dpkg --set-selections < "$backup_file"; then
                apt-get dselect-upgrade -y
                log_message "SUCCESS" "Restauration APT réussie"
            else
                log_message "ERROR" "Échec de la restauration APT"
                return 1
            fi
            ;;
        "dnf"|"yum")
            log_message "INFO" "Restauration des paquets RPM..."
            while IFS= read -r package; do
                if [[ -n "$package" ]] && [[ ! "$package" =~ ^# ]]; then
                    $RESTORE_CMD "$package" || log_message "WARNING" "Échec installation: $package"
                fi
            done < "$backup_file"
            log_message "SUCCESS" "Restauration RPM terminée"
            ;;
        "pacman")
            log_message "INFO" "Restauration des paquets Pacman..."
            pacman -S --needed --noconfirm $(cat "$backup_file")
            log_message "SUCCESS" "Restauration Pacman réussie"
            ;;
        "zypper")
            log_message "INFO" "Restauration des paquets Zypper..."
            while IFS= read -r package; do
                if [[ -n "$package" ]] && [[ ! "$package" =~ ^# ]]; then
                    zypper install -y "$package" || log_message "WARNING" "Échec installation: $package"
                fi
            done < "$backup_file"
            log_message "SUCCESS" "Restauration Zypper terminée"
            ;;
    esac
    
    log_message "SUCCESS" "Restauration de la sauvegarde $backup_name terminée"
    return 0
}

# ========================================================================
# FONCTION: Extraction et installation des paquets
# ========================================================================
install_packages() {
    local package_file="$1"
    local packages_to_install=()
    local install_count=0
    local failed_count=0
    
    log_message "INFO" "Analyse du fichier de paquets: $(basename "$package_file")"
    
    # Extraction des noms de paquets (format simplifié: un paquet par ligne)
    while IFS= read -r line; do
        # Ignorer les commentaires et lignes vides
        if [[ ! "$line" =~ ^# ]] && [[ -n "$line" ]]; then
            # Nettoyer le nom du paquet (enlever les espaces)
            package=$(echo "$line" | xargs)
            if [[ -n "$package" ]]; then
                packages_to_install+=("$package")
            fi
        fi
    done < "$package_file"
    
    log_message "INFO" "${#packages_to_install[@]} paquets à installer"
    
    if [[ ${#packages_to_install[@]} -eq 0 ]]; then
        log_message "WARNING" "Aucun paquet à installer trouvé"
        return 0
    fi
    
    # Installation des paquets par lots pour éviter les timeouts
    local batch_size=10
    for ((i=0; i<${#packages_to_install[@]}; i+=batch_size)); do
        local batch=("${packages_to_install[@]:i:batch_size}")
        
        log_message "INFO" "Installation du lot ${i}/${#packages_to_install[@]}: ${batch[*]}"
        
        if $INSTALL_CMD "${batch[@]}"; then
            ((install_count+=${#batch[@]}))
            log_message "SUCCESS" "Lot installé: ${batch[*]}"
        else
            ((failed_count+=${#batch[@]}))
            log_message "ERROR" "Échec du lot: ${batch[*]}"
            
            # Tentative d'installation individuelle en cas d'échec du lot
            for package in "${batch[@]}"; do
                log_message "INFO" "Tentative d'installation individuelle: $package"
                if $INSTALL_CMD "$package"; then
                    ((install_count++))
                    ((failed_count--))
                    log_message "SUCCESS" "Installation réussie: $package"
                else
                    log_message "ERROR" "Échec d'installation: $package"
                fi
            done
        fi
    done
    
    log_message "SUCCESS" "Installation terminée: $install_count réussies, $failed_count échecs"
    
    if [[ $failed_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ========================================================================
# FONCTION: Gestion des arguments de ligne de commande
# ========================================================================
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup)
                AUTO_BACKUP=true
                shift
                ;;
            --restore)
                if [[ -n "${2:-}" ]]; then
                    RESTORE_MODE=true
                    RESTORE_NAME="$2"
                    shift 2
                else
                    log_message "ERROR" "Nom de sauvegarde requis pour --restore"
                    exit 1
                fi
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_message "ERROR" "Argument inconnu: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# ========================================================================
# FONCTION: Confirmation utilisateur
# ========================================================================
confirm_action() {
    local message="$1"
    local response
    
    echo "$message"
    read -p "Continuer? (y/N): " response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ========================================================================
# FONCTION PRINCIPALE
# ========================================================================
main() {
    # Variables pour les arguments
    local AUTO_BACKUP=false
    local RESTORE_MODE=false
    local RESTORE_NAME=""
    
    echo "=========================================="
    echo "Auto-Patching Manager - Install Script"
    echo "=========================================="
    
    # Parsing des arguments
    parse_arguments "$@"
    
    # Vérifications préliminaires
    check_root
    create_directories
    
    # Initialisation du log
    log_message "INFO" "Démarrage du script install.sh"
    log_message "INFO" "Timestamp: $TIMESTAMP"
    
    detect_distribution
    
    # Mode restauration
    if [[ "$RESTORE_MODE" = true ]]; then
        log_message "INFO" "Mode restauration activé pour: $RESTORE_NAME"
        if restore_backup "$RESTORE_NAME"; then
            log_message "SUCCESS" "Restauration terminée avec succès"
            exit 0
        else
            log_message "ERROR" "Échec de la restauration"
            exit 5
        fi
    fi
    
    # Mode installation normale
    local package_file
    package_file=$(find_latest_package_list)
    
    # Gestion de la sauvegarde
    if [[ "$AUTO_BACKUP" = true ]]; then
        log_message "INFO" "Sauvegarde automatique demandée"
        create_backup
    else
        echo "=========================================="
        echo "RECOMMANDATION: Création d'une sauvegarde"
        echo "=========================================="
        if confirm_action "Voulez-vous créer une sauvegarde avant l'installation?"; then
            create_backup
        else
            log_message "WARNING" "Installation sans sauvegarde - risque élevé"
        fi
    fi
    
    # Confirmation d'installation
    echo "=========================================="
    echo "INSTALLATION DES MISES À JOUR"
    echo "=========================================="
    echo "Fichier source: $(basename "$package_file")"
    echo "Distribution: $DISTRO ($PACKAGE_MANAGER)"
    echo ""
    
    if ! confirm_action "Procéder à l'installation des mises à jour?"; then
        log_message "INFO" "Installation annulée par l'utilisateur"
        exit 0
    fi
    
    # Installation des paquets
    if install_packages "$package_file"; then
        log_message "SUCCESS" "Installation terminée avec succès"
        echo "=========================================="
        echo "Installation réussie!"
        echo "Consultez les logs: $LOG_FILE"
        echo "=========================================="
        exit 0
    else
        log_message "ERROR" "Des erreurs sont survenues pendant l'installation"
        echo "=========================================="
        echo "Installation terminée avec des erreurs"
        echo "Consultez les logs: $LOG_FILE"
        echo "Utilisez rollback.sh si nécessaire"
        echo "=========================================="
        exit 6
    fi
}

# Exécution du script principal
main "$@"
