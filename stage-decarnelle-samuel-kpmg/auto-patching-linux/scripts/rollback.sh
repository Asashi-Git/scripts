#!/bin/bash

# ========================================================================
# Script: rollback.sh
# Description: Gestion des sauvegardes système et restauration d'état antérieur
# Usage: ./rollback.sh [restore <backup_name>|create [backup_name]|delete <backup_name>|list]
# Author: Decarnelle Samuel
# Version: 1.0
# ========================================================================
# Ce script permet la gestion complète des sauvegardes système générées
# par install.sh, incluant la restauration, création rapide, suppression
# et listage des sauvegardes disponibles.
# ========================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Configuration globale
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BASE_DIR}/backups"
LOG_DIR="${BASE_DIR}/log"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="${LOG_DIR}/rollback_${TIMESTAMP}.log"

# Variables globales pour la distribution
DISTRO=""
PACKAGE_MANAGER=""
INSTALL_CMD=""
REMOVE_CMD=""
LIST_INSTALLED_CMD=""
BACKUP_CMD=""
RESTORE_CMD=""

# ========================================================================
# FONCTION: Vérification des privilèges root
# ========================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERREUR: Ce script doit être exécuté en tant que root (sudo)." >&2
        echo "Usage: sudo $0 [restore|create|delete|list] [backup_name]" >&2
        exit 1
    fi
}

# ========================================================================
# FONCTION: Affichage de l'aide
# ========================================================================
show_help() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

COMMANDES:
    list                    Lister toutes les sauvegardes disponibles
    create [NAME]           Créer une nouvelle sauvegarde (nom optionnel)
    restore <NAME>          Restaurer une sauvegarde spécifique
    delete <NAME>           Supprimer une sauvegarde obsolète
    interactive             Mode interactif (défaut si aucun argument)

EXEMPLES:
    sudo $0                           # Mode interactif
    sudo $0 list                      # Lister les sauvegardes
    sudo $0 create                    # Créer une sauvegarde rapide
    sudo $0 create mysave             # Créer une sauvegarde nommée
    sudo $0 restore backup_2024-01-15 # Restaurer une sauvegarde
    sudo $0 delete old_backup         # Supprimer une sauvegarde

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
        "CRITICAL") echo -e "\033[41m[$timestamp] [CRITICAL] $message\033[0m" ;;
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
                REMOVE_CMD="apt remove -y"
                LIST_INSTALLED_CMD="dpkg-query -W -f='\${Package} \${Version} \${Status}\n'"
                BACKUP_CMD="dpkg --get-selections"
                RESTORE_CMD="dpkg --set-selections"
                ;;
            "fedora"|"rhel"|"centos"|"rocky"|"almalinux")
                if command -v dnf >/dev/null 2>&1; then
                    distro="fedora"
                    package_manager="dnf"
                    INSTALL_CMD="dnf install -y"
                    REMOVE_CMD="dnf remove -y"
                    LIST_INSTALLED_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'"
                    BACKUP_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'"
                    RESTORE_CMD="dnf install -y"
                elif command -v yum >/dev/null 2>&1; then
                    distro="rhel"
                    package_manager="yum"
                    INSTALL_CMD="yum install -y"
                    REMOVE_CMD="yum remove -y"
                    LIST_INSTALLED_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'"
                    BACKUP_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'"
                    RESTORE_CMD="yum install -y"
                fi
                ;;
            "arch"|"manjaro"|"endeavouros")
                distro="arch"
                package_manager="pacman"
                INSTALL_CMD="pacman -S --noconfirm"
                REMOVE_CMD="pacman -R --noconfirm"
                LIST_INSTALLED_CMD="pacman -Q"
                BACKUP_CMD="pacman -Qq"
                RESTORE_CMD="pacman -S --noconfirm"
                ;;
            "opensuse"|"opensuse-leap"|"opensuse-tumbleweed")
                distro="opensuse"
                package_manager="zypper"
                INSTALL_CMD="zypper install -y"
                REMOVE_CMD="zypper remove -y"
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
            REMOVE_CMD="apt remove -y"
            LIST_INSTALLED_CMD="dpkg-query -W -f='\${Package} \${Version} \${Status}\n'"
            BACKUP_CMD="dpkg --get-selections"
            RESTORE_CMD="dpkg --set-selections"
        elif command -v dnf >/dev/null 2>&1; then
            distro="fedora"
            package_manager="dnf"
            INSTALL_CMD="dnf install -y"
            REMOVE_CMD="dnf remove -y"
            LIST_INSTALLED_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'"
            BACKUP_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'"
            RESTORE_CMD="dnf install -y"
        elif command -v yum >/dev/null 2>&1; then
            distro="rhel"
            package_manager="yum"
            INSTALL_CMD="yum install -y"
            REMOVE_CMD="yum remove -y"
            LIST_INSTALLED_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n'"
            BACKUP_CMD="rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'"
            RESTORE_CMD="yum install -y"
        elif command -v pacman >/dev/null 2>&1; then
            distro="arch"
            package_manager="pacman"
            INSTALL_CMD="pacman -S --noconfirm"
            REMOVE_CMD="pacman -R --noconfirm"
            LIST_INSTALLED_CMD="pacman -Q"
            BACKUP_CMD="pacman -Qq"
            RESTORE_CMD="pacman -S --noconfirm"
        elif command -v zypper >/dev/null 2>&1; then
            distro="opensuse"
            package_manager="zypper"
            INSTALL_CMD="zypper install -y"
            REMOVE_CMD="zypper remove -y"
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
}

# ========================================================================
# FONCTION: Liste détaillée des sauvegardes disponibles
# ========================================================================
list_backups() {
    log_message "INFO" "Listing des sauvegardes disponibles"
    
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR"/*.backup 2>/dev/null)" ]]; then
        log_message "WARNING" "Aucune sauvegarde trouvée dans $BACKUP_DIR"
        echo "Aucune sauvegarde disponible."
        echo "Utilisez 'create' pour créer une nouvelle sauvegarde."
        return 1
    fi
    
    echo "=========================================="
    echo "SAUVEGARDES DISPONIBLES"
    echo "=========================================="
    printf "%-25s %-20s %-10s %-15s\n" "NOM" "DATE CRÉATION" "PAQUETS" "TAILLE"
    echo "--------------------------------------------------------------------------"
    
    local count=0
    for backup in "$BACKUP_DIR"/*.backup; do
        if [[ -f "$backup" ]]; then
            local name=$(basename "$backup" .backup)
            local metadata="${BACKUP_DIR}/${name}.metadata"
            local date="N/A"
            local package_count="N/A"
            local size="N/A"
            local hostname="N/A"
            local distro="N/A"
            
            if [[ -f "$metadata" ]]; then
                date=$(grep "CREATION_DATE=" "$metadata" 2>/dev/null | cut -d'=' -f2- | cut -d' ' -f1-2 2>/dev/null || echo "N/A")
                package_count=$(grep "BACKUP_SIZE=" "$metadata" 2>/dev/null | cut -d'=' -f2 || echo "N/A")
                hostname=$(grep "HOSTNAME=" "$metadata" 2>/dev/null | cut -d'=' -f2 || echo "N/A")
                distro=$(grep "DISTRO=" "$metadata" 2>/dev/null | cut -d'=' -f2 || echo "N/A")
            fi
            
            if [[ "$package_count" == "N/A" ]]; then
                package_count=$(wc -l < "$backup" 2>/dev/null || echo "N/A")
            fi
            
            size=$(ls -lh "$backup" 2>/dev/null | awk '{print $5}' || echo "N/A")
            
            printf "%-25s %-20s %-10s %-15s\n" "$name" "$date" "$package_count" "$size"
            
            # Affichage des détails si métadonnées disponibles
            if [[ -f "$metadata" ]]; then
                echo "    └─ Host: $hostname, Distribution: $distro"
            fi
            
            ((count++))
        fi
    done
    
    echo "--------------------------------------------------------------------------"
    echo "Total: $count sauvegarde(s) disponible(s)"
    echo "=========================================="
    
    return 0
}

# ========================================================================
# FONCTION: Création d'une sauvegarde rapide
# ========================================================================
create_backup() {
    local backup_name="${1:-quick_backup_${TIMESTAMP}}"
    local backup_file="${BACKUP_DIR}/${backup_name}.backup"
    local metadata_file="${BACKUP_DIR}/${backup_name}.metadata"
    
    # Vérification si la sauvegarde existe déjà
    if [[ -f "$backup_file" ]]; then
        log_message "ERROR" "Une sauvegarde avec ce nom existe déjà: $backup_name"
        return 1
    fi
    
    log_message "INFO" "Création de la sauvegarde rapide: $backup_name"
    
    # Création du fichier de sauvegarde principal
    case "$PACKAGE_MANAGER" in
        "apt")
            log_message "INFO" "Sauvegarde des sélections de paquets Debian/Ubuntu..."
            if ! dpkg --get-selections > "$backup_file"; then
                log_message "ERROR" "Échec de la sauvegarde APT"
                return 1
            fi
            dpkg-query -W -f='${Package} ${Version} ${Status}\n' > "${backup_file}.detailed" 2>/dev/null || true
            ;;
        "dnf"|"yum"|"zypper")
            log_message "INFO" "Sauvegarde des paquets RPM..."
            if ! eval "$BACKUP_CMD" > "$backup_file"; then
                log_message "ERROR" "Échec de la sauvegarde RPM"
                return 1
            fi
            eval "$LIST_INSTALLED_CMD" > "${backup_file}.detailed" 2>/dev/null || true
            ;;
        "pacman")
            log_message "INFO" "Sauvegarde des paquets Pacman..."
            if ! pacman -Qq > "$backup_file"; then
                log_message "ERROR" "Échec de la sauvegarde Pacman"
                return 1
            fi
            pacman -Q > "${backup_file}.detailed" 2>/dev/null || true
            ;;
    esac
    
    # Création des métadonnées détaillées
    cat > "$metadata_file" << EOF
# Métadonnées de sauvegarde - Auto-Patching Manager
BACKUP_NAME=$backup_name
TIMESTAMP=$TIMESTAMP
DISTRO=$DISTRO
PACKAGE_MANAGER=$PACKAGE_MANAGER
CREATION_DATE=$(date)
HOSTNAME=$(hostname)
KERNEL_VERSION=$(uname -r)
BACKUP_SIZE=$(wc -l < "$backup_file")
USER=$USER
SCRIPT_VERSION=1.0
BACKUP_TYPE=QUICK
EOF
    
    # Calcul des checksums pour vérification d'intégrité
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$backup_file" > "${backup_file}.sha256"
        log_message "SUCCESS" "Checksum SHA256 généré pour vérification d'intégrité"
    fi
    
    # Application des permissions appropriées
    chmod 644 "$backup_file" "$metadata_file"
    [[ -f "${backup_file}.detailed" ]] && chmod 644 "${backup_file}.detailed"
    [[ -f "${backup_file}.sha256" ]] && chmod 644 "${backup_file}.sha256"
    
    local package_count=$(wc -l < "$backup_file")
    log_message "SUCCESS" "Sauvegarde rapide créée: $backup_name ($package_count paquets)"
    
    echo "=========================================="
    echo "SAUVEGARDE CRÉÉE AVEC SUCCÈS"
    echo "=========================================="
    echo "Nom: $backup_name"
    echo "Paquets sauvegardés: $package_count"
    echo "Emplacement: $backup_file"
    echo "=========================================="
    
    return 0
}

# ========================================================================
# FONCTION: Restauration d'une sauvegarde avec validation complète
# ========================================================================
restore_backup() {
    local backup_name="$1"
    local backup_file="${BACKUP_DIR}/${backup_name}.backup"
    local metadata_file="${BACKUP_DIR}/${backup_name}.metadata"
    
    log_message "INFO" "Tentative de restauration de la sauvegarde: $backup_name"
    
    # Vérifications préliminaires
    if [[ ! -f "$backup_file" ]]; then
        log_message "ERROR" "Sauvegarde introuvable: $backup_name"
        log_message "ERROR" "Chemin recherché: $backup_file"
        return 1
    fi
    
    # Vérification de la compatibilité de distribution
    if [[ -f "$metadata_file" ]]; then
        local backup_distro=$(grep "DISTRO=" "$metadata_file" 2>/dev/null | cut -d'=' -f2 || echo "unknown")
        local backup_pm=$(grep "PACKAGE_MANAGER=" "$metadata_file" 2>/dev/null | cut -d'=' -f2 || echo "unknown")
        
        if [[ "$backup_distro" != "$DISTRO" ]] || [[ "$backup_pm" != "$PACKAGE_MANAGER" ]]; then
            log_message "WARNING" "Incompatibilité détectée:"
            log_message "WARNING" "  Sauvegarde: $backup_distro ($backup_pm)"
            log_message "WARNING" "  Système actuel: $DISTRO ($PACKAGE_MANAGER)"
            
            echo "ATTENTION: Incompatibilité de distribution détectée!"
            echo "Cette restauration pourrait échouer ou corrompre le système."
            read -p "Voulez-vous vraiment continuer? (y/N): " response
            case "$response" in
                [yY]|[yY][eE][sS])
                    log_message "WARNING" "Restauration forcée par l'utilisateur"
                    ;;
                *)
                    log_message "INFO" "Restauration annulée par l'utilisateur"
                    return 1
                    ;;
            esac
        fi
    fi
    
    # Vérification de l'intégrité
    if [[ -f "${backup_file}.sha256" ]]; then
        log_message "INFO" "Vérification de l'intégrité de la sauvegarde..."
        if sha256sum -c "${backup_file}.sha256" &>/dev/null; then
            log_message "SUCCESS" "Vérification d'intégrité réussie"
        else
            log_message "CRITICAL" "ÉCHEC de la vérification d'intégrité!"
            log_message "CRITICAL" "La sauvegarde pourrait être corrompue"
            
            echo "ERREUR CRITIQUE: Échec de la vérification d'intégrité!"
            echo "La sauvegarde pourrait être corrompue ou modifiée."
            read -p "Voulez-vous continuer malgré tout? (y/N): " response
            case "$response" in
                [yY]|[yY][eE][sS])
                    log_message "CRITICAL" "Restauration forcée malgré l'échec d'intégrité"
                    ;;
                *)
                    log_message "INFO" "Restauration annulée - intégrité compromise"
                    return 1
                    ;;
            esac
        fi
    else
        log_message "WARNING" "Aucun checksum disponible - impossible de vérifier l'intégrité"
    fi
    
    # Création d'une sauvegarde de sécurité avant restauration
    log_message "INFO" "Création d'une sauvegarde de sécurité avant restauration..."
    if ! create_backup "pre_restore_${TIMESTAMP}"; then
        log_message "ERROR" "Impossible de créer la sauvegarde de sécurité"
        log_message "ERROR" "Restauration annulée pour éviter la perte de données"
        return 1
    fi
    
    # Confirmation finale
    echo "=========================================="
    echo "CONFIRMATION DE RESTAURATION"
    echo "=========================================="
    echo "Sauvegarde à restaurer: $backup_name"
    if [[ -f "$metadata_file" ]]; then
        echo "Date de création: $(grep "CREATION_DATE=" "$metadata_file" | cut -d'=' -f2-)"
        echo "Nombre de paquets: $(grep "BACKUP_SIZE=" "$metadata_file" | cut -d'=' -f2)"
    fi
    echo ""
    echo "ATTENTION: Cette opération va modifier l'état de votre système!"
    echo "Une sauvegarde de sécurité a été créée: pre_restore_${TIMESTAMP}"
    echo ""
    
    read -p "Confirmer la restauration? (y/N): " response
    case "$response" in
        [yY]|[yY][eE][sS])
            ;;
        *)
            log_message "INFO" "Restauration annulée par l'utilisateur"
            return 1
            ;;
    esac
    
    # Processus de restauration selon le gestionnaire de paquets
    log_message "INFO" "Démarrage de la restauration pour $PACKAGE_MANAGER..."
    
    case "$PACKAGE_MANAGER" in
        "apt")
            log_message "INFO" "Restauration des sélections de paquets APT..."
            
            # Réinitialisation des sélections
            if dpkg --set-selections < "$backup_file"; then
                log_message "SUCCESS" "Sélections de paquets restaurées"
                
                # Application des changements
                log_message "INFO" "Application des changements..."
                if apt-get dselect-upgrade -y; then
                    log_message "SUCCESS" "Restauration APT réussie"
                else
                    log_message "ERROR" "Échec de l'application des changements APT"
                    return 1
                fi
            else
                log_message "ERROR" "Échec de la restauration des sélections APT"
                return 1
            fi
            ;;
            
        "dnf"|"yum")
            log_message "INFO" "Restauration des paquets RPM via $PACKAGE_MANAGER..."
            
            local success_count=0
            local error_count=0
            local total_packages=$(wc -l < "$backup_file")
            
            while IFS= read -r package; do
                if [[ -n "$package" ]] && [[ ! "$package" =~ ^# ]]; then
                    log_message "INFO" "Installation: $package"
                    if $RESTORE_CMD "$package" &>/dev/null; then
                        ((success_count++))
                    else
                        ((error_count++))
                        log_message "WARNING" "Échec installation: $package"
                    fi
                fi
            done < "$backup_file"
            
            log_message "SUCCESS" "Restauration RPM terminée: $success_count/$total_packages réussies"
            if [[ $error_count -gt 0 ]]; then
                log_message "WARNING" "$error_count paquets n'ont pas pu être restaurés"
            fi
            ;;
            
        "pacman")
            log_message "INFO" "Restauration des paquets Pacman..."
            
            # Installation des paquets de la sauvegarde
            if pacman -S --needed --noconfirm $(cat "$backup_file"); then
                log_message "SUCCESS" "Restauration Pacman réussie"
            else
                log_message "ERROR" "Échec de la restauration Pacman"
                return 1
            fi
            ;;
            
        "zypper")
            log_message "INFO" "Restauration des paquets Zypper..."
            
            local success_count=0
            local error_count=0
            local total_packages=$(wc -l < "$backup_file")
            
            while IFS= read -r package; do
                if [[ -n "$package" ]] && [[ ! "$package" =~ ^# ]]; then
                    log_message "INFO" "Installation: $package"
                    if zypper install -y "$package" &>/dev/null; then
                        ((success_count++))
                    else
                        ((error_count++))
                        log_message "WARNING" "Échec installation: $package"
                    fi
                fi
            done < "$backup_file"
            
            log_message "SUCCESS" "Restauration Zypper terminée: $success_count/$total_packages réussies"
            if [[ $error_count -gt 0 ]]; then
                log_message "WARNING" "$error_count paquets n'ont pas pu être restaurés"
            fi
            ;;
    esac
    
    log_message "SUCCESS" "Restauration de la sauvegarde $backup_name terminée"
    
    echo "=========================================="
    echo "RESTAURATION TERMINÉE"
    echo "=========================================="
    echo "Sauvegarde restaurée: $backup_name"
    echo "Sauvegarde de sécurité: pre_restore_${TIMESTAMP}"
    echo "Consultez les logs: $LOG_FILE"
    echo "=========================================="
    
    return 0
}

# ========================================================================
# FONCTION: Suppression sécurisée d'une sauvegarde
# ========================================================================
delete_backup() {
    local backup_name="$1"
    local backup_file="${BACKUP_DIR}/${backup_name}.backup"
    local metadata_file="${BACKUP_DIR}/${backup_name}.metadata"
    local detailed_file="${backup_file}.detailed"
    local checksum_file="${backup_file}.sha256"
    
    log_message "INFO" "Tentative de suppression de la sauvegarde: $backup_name"
    
    # Vérification de l'existence
    if [[ ! -f "$backup_file" ]]; then
        log_message "ERROR" "Sauvegarde introuvable: $backup_name"
        return 1
    fi
    
    # Affichage des informations avant suppression
    echo "=========================================="
    echo "SUPPRESSION DE SAUVEGARDE"
    echo "=========================================="
    echo "Nom: $backup_name"
    
    if [[ -f "$metadata_file" ]]; then
        echo "Date de création: $(grep "CREATION_DATE=" "$metadata_file" | cut -d'=' -f2-)"
        echo "Nombre de paquets: $(grep "BACKUP_SIZE=" "$metadata_file" | cut -d'=' -f2)"
        echo "Distribution: $(grep "DISTRO=" "$metadata_file" | cut -d'=' -f2)"
    fi
    
    echo "Emplacement: $backup_file"
    echo ""
    echo "ATTENTION: Cette action est irréversible!"
    
    # Confirmation
    read -p "Confirmer la suppression? (y/N): " response
    case "$response" in
        [yY]|[yY][eE][sS])
            ;;
        *)
            log_message "INFO" "Suppression annulée par l'utilisateur"
            return 1
            ;;
    esac
    
    # Suppression des fichiers associés
    local deleted_files=0
    
    for file in "$backup_file" "$metadata_file" "$detailed_file" "$checksum_file"; do
        if [[ -f "$file" ]]; then
            if rm -f "$file"; then
                log_message "SUCCESS" "Fichier supprimé: $(basename "$file")"
                ((deleted_files++))
            else
                log_message "ERROR" "Échec suppression: $(basename "$file")"
            fi
        fi
    done
    
    if [[ $deleted_files -gt 0 ]]; then
        log_message "SUCCESS" "Sauvegarde $backup_name supprimée ($deleted_files fichiers)"
        
        echo "=========================================="
        echo "SUPPRESSION RÉUSSIE"
        echo "=========================================="
        echo "Sauvegarde supprimée: $backup_name"
        echo "Fichiers supprimés: $deleted_files"
        echo "=========================================="
        
        return 0
    else
        log_message "ERROR" "Aucun fichier n'a pu être supprimé"
        return 1
    fi
}

# ========================================================================
# FONCTION: Mode interactif
# ========================================================================
interactive_mode() {
    while true; do
        echo ""
        echo "=========================================="
        echo "AUTO-PATCHING MANAGER - ROLLBACK"
        echo "=========================================="
        echo "1. Lister les sauvegardes disponibles"
        echo "2. Créer une nouvelle sauvegarde rapide"
        echo "3. Restaurer une sauvegarde"
        echo "4. Supprimer une sauvegarde"
        echo "5. Quitter"
        echo "=========================================="
        
        read -p "Choisissez une option (1-5): " choice
        
        case $choice in
            1)
                echo ""
                list_backups
                ;;
            2)
                echo ""
                read -p "Nom de la sauvegarde (optionnel): " backup_name
                if [[ -z "$backup_name" ]]; then
                    create_backup
                else
                    create_backup "$backup_name"
                fi
                ;;
            3)
                echo ""
                if list_backups; then
                    echo ""
                    read -p "Nom de la sauvegarde à restaurer: " backup_name
                    if [[ -n "$backup_name" ]]; then
                        restore_backup "$backup_name"
                    else
                        echo "Nom de sauvegarde requis."
                    fi
                else
                    echo "Aucune sauvegarde disponible pour la restauration."
                fi
                ;;
            4)
                echo ""
                if list_backups; then
                    echo ""
                    read -p "Nom de la sauvegarde à supprimer: " backup_name
                    if [[ -n "$backup_name" ]]; then
                        delete_backup "$backup_name"
                    else
                        echo "Nom de sauvegarde requis."
                    fi
                else
                    echo "Aucune sauvegarde disponible pour la suppression."
                fi
                ;;
            5)
                log_message "INFO" "Sortie du mode interactif"
                echo "Au revoir!"
                exit 0
                ;;
            *)
                echo "Option invalide. Veuillez choisir entre 1 et 5."
                ;;
        esac
        
        read -p "Appuyez sur Entrée pour continuer..."
    done
}

# ========================================================================
# FONCTION: Gestion des arguments de ligne de commande
# ========================================================================
parse_arguments() {
    case "${1:-}" in
        "list")
            list_backups
            exit $?
            ;;
        "create")
            if [[ -n "${2:-}" ]]; then
                create_backup "$2"
            else
                create_backup
            fi
            exit $?
            ;;
        "restore")
            if [[ -n "${2:-}" ]]; then
                restore_backup "$2"
                exit $?
            else
                log_message "ERROR" "Nom de sauvegarde requis pour la restauration"
                echo "Usage: $0 restore <backup_name>"
                exit 1
            fi
            ;;
        "delete")
            if [[ -n "${2:-}" ]]; then
                delete_backup "$2"
                exit $?
            else
                log_message "ERROR" "Nom de sauvegarde requis pour la suppression"
                echo "Usage: $0 delete <backup_name>"
                exit 1
            fi
            ;;
        "interactive"|"")
            interactive_mode
            ;;
        "--help"|"-h")
            show_help
            exit 0
            ;;
        *)
            log_message "ERROR" "Commande inconnue: ${1:-}"
            show_help
            exit 1
            ;;
    esac
}

# ========================================================================
# FONCTION PRINCIPALE
# ========================================================================
main() {
    echo "=========================================="
    echo "Auto-Patching Manager - Rollback Script"
    echo "=========================================="
    
    # Vérifications préliminaires
    check_root
    create_directories
    
    # Initialisation du log
    log_message "INFO" "Démarrage du script rollback.sh"
    log_message "INFO" "Timestamp: $TIMESTAMP"
    log_message "INFO" "Arguments: $*"
    
    detect_distribution
    
    # Parsing et exécution des commandes
    parse_arguments "$@"
}

# Exécution du script principal
main "$@"
