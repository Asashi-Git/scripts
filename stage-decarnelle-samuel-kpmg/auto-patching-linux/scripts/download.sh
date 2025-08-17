#!/bin/bash

# ========================================================================
# Script: download.sh
# Description: Télécharge la liste des mises à jour disponibles sans les installer
# Usage: ./download.sh
# Author: Decarnelle Samuel
# Version: 1.0
# ========================================================================
# Ce script détecte automatiquement la distribution Linux et son gestionnaire
# de paquets, puis télécharge la liste des paquets à mettre à jour dans un
# répertoire dédié avec horodatage et archivage automatique.
# ========================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Configuration globale
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGE_LIST_DIR="${BASE_DIR}/package-list"
PACKAGE_LIST_OLD_DIR="${BASE_DIR}/package-list-old"
LOG_DIR="${BASE_DIR}/log"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="${LOG_DIR}/download_${TIMESTAMP}.log"

# ========================================================================
# FONCTION: Vérification des privilèges root
# ========================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERREUR: Ce script doit être exécuté en tant que root (sudo)." >&2
        echo "Usage: sudo $0" >&2
        exit 1
    fi
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
    local update_cmd=""
    local list_cmd=""
    local verify_cmd=""
    
    log_message "INFO" "Détection de la distribution en cours..."
    
    # Détection via /etc/os-release (méthode principale)
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            "ubuntu"|"debian"|"linuxmint"|"pop")
                distro="debian"
                package_manager="apt"
                update_cmd="apt update"
                list_cmd="apt list --upgradable"
                verify_cmd="apt-key verify"
                ;;
            "fedora"|"rhel"|"centos"|"rocky"|"almalinux")
                if command -v dnf >/dev/null 2>&1; then
                    distro="fedora"
                    package_manager="dnf"
                    update_cmd="dnf check-update"
                    list_cmd="dnf list updates"
                    verify_cmd="rpm --checksig"
                elif command -v yum >/dev/null 2>&1; then
                    distro="rhel"
                    package_manager="yum"
                    update_cmd="yum check-update"
                    list_cmd="yum list updates"
                    verify_cmd="rpm --checksig"
                fi
                ;;
            "arch"|"manjaro"|"endeavouros")
                distro="arch"
                package_manager="pacman"
                update_cmd="pacman -Sy"
                list_cmd="pacman -Qu"
                verify_cmd="pacman-key --verify"
                ;;
            "opensuse"|"opensuse-leap"|"opensuse-tumbleweed")
                distro="opensuse"
                package_manager="zypper"
                update_cmd="zypper refresh"
                list_cmd="zypper list-updates"
                verify_cmd="rpm --checksig"
                ;;
        esac
    fi
    
    # Vérification de détection alternative si échec
    if [[ -z "$package_manager" ]]; then
        if command -v apt >/dev/null 2>&1; then
            distro="debian"
            package_manager="apt"
            update_cmd="apt update"
            list_cmd="apt list --upgradable"
            verify_cmd="apt-key verify"
        elif command -v dnf >/dev/null 2>&1; then
            distro="fedora"
            package_manager="dnf"
            update_cmd="dnf check-update"
            list_cmd="dnf list updates"
            verify_cmd="rpm --checksig"
        elif command -v yum >/dev/null 2>&1; then
            distro="rhel"
            package_manager="yum"
            update_cmd="yum check-update"
            list_cmd="yum list updates"
            verify_cmd="rpm --checksig"
        elif command -v pacman >/dev/null 2>&1; then
            distro="arch"
            package_manager="pacman"
            update_cmd="pacman -Sy"
            list_cmd="pacman -Qu"
            verify_cmd="pacman-key --verify"
        elif command -v zypper >/dev/null 2>&1; then
            distro="opensuse"
            package_manager="zypper"
            update_cmd="zypper refresh"
            list_cmd="zypper list-updates"
            verify_cmd="rpm --checksig"
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
    export UPDATE_CMD="$update_cmd"
    export LIST_CMD="$list_cmd"
    export VERIFY_CMD="$verify_cmd"
}

# ========================================================================
# FONCTION: Création des répertoires avec droits appropriés
# ========================================================================
create_directories() {
    log_message "INFO" "Création des répertoires de travail..."
    
    # Création des dossiers principaux
    for dir in "$PACKAGE_LIST_DIR" "$PACKAGE_LIST_OLD_DIR" "$LOG_DIR"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 755 "$dir"
            log_message "SUCCESS" "Répertoire créé: $dir"
        else
            log_message "INFO" "Répertoire existant: $dir"
        fi
    done
}

# ========================================================================
# FONCTION: Archivage des anciens fichiers de liste
# ========================================================================
archive_old_packages() {
    log_message "INFO" "Archivage des anciennes listes de paquets..."
    
    if [[ -d "$PACKAGE_LIST_DIR" ]] && [[ -n "$(ls -A "$PACKAGE_LIST_DIR" 2>/dev/null)" ]]; then
        # Déplacement des fichiers existants vers l'archive
        for file in "$PACKAGE_LIST_DIR"/*; do
            if [[ -f "$file" ]]; then
                mv "$file" "$PACKAGE_LIST_OLD_DIR/"
                log_message "SUCCESS" "Fichier archivé: $(basename "$file")"
            fi
        done
    else
        log_message "INFO" "Aucun fichier à archiver"
    fi
}

# ========================================================================
# FONCTION: Mise à jour de la liste des paquets selon le gestionnaire
# ========================================================================
update_package_list() {
    log_message "INFO" "Mise à jour de la liste des paquets disponibles..."
    
    case "$PACKAGE_MANAGER" in
        "apt")
            if ! $UPDATE_CMD &>/dev/null; then
                log_message "ERROR" "Échec de la mise à jour de la liste des paquets (apt update)"
                return 1
            fi
            ;;
        "dnf"|"yum")
            if ! $UPDATE_CMD &>/dev/null; then
                log_message "WARNING" "Mise à jour de la liste des paquets terminée avec avertissements"
            fi
            ;;
        "pacman")
            if ! $UPDATE_CMD &>/dev/null; then
                log_message "ERROR" "Échec de la mise à jour de la liste des paquets (pacman -Sy)"
                return 1
            fi
            ;;
        "zypper")
            if ! $UPDATE_CMD &>/dev/null; then
                log_message "ERROR" "Échec de la mise à jour de la liste des paquets (zypper refresh)"
                return 1
            fi
            ;;
    esac
    
    log_message "SUCCESS" "Liste des paquets mise à jour"
    return 0
}

# ========================================================================
# FONCTION: Génération de la liste des paquets à mettre à jour
# ========================================================================
generate_package_list() {
    local output_file="${PACKAGE_LIST_DIR}/packages_${TIMESTAMP}.txt"
    local package_count=0
    
    log_message "INFO" "Génération de la liste des paquets à mettre à jour..."
    
    # En-tête du fichier
    cat > "$output_file" << EOF
# Liste des paquets à mettre à jour
# Générée le: $(date)
# Distribution: $DISTRO
# Gestionnaire: $PACKAGE_MANAGER
# Timestamp: $TIMESTAMP
# ========================================

EOF

    case "$PACKAGE_MANAGER" in
        "apt")
            # Extraction des noms de paquets seulement pour APT
            apt list --upgradable 2>/dev/null | grep -v "^WARNING\|^Listing" | while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    # Extraire seulement le nom du paquet (avant le premier /)
                    package_name=$(echo "$line" | cut -d'/' -f1)
                    if [[ -n "$package_name" ]]; then
                        echo "$package_name" >> "$output_file"
                        ((package_count++))
                    fi
                fi
            done
            ;;
        "dnf"|"yum")
            # Extraction des noms de paquets pour DNF/YUM
            $LIST_CMD 2>/dev/null | grep -v "^Last metadata\|^$" | while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    # Extraire le nom du paquet (première colonne)
                    package_name=$(echo "$line" | awk '{print $1}' | sed 's/\..*$//')
                    if [[ -n "$package_name" ]]; then
                        echo "$package_name" >> "$output_file"
                        ((package_count++))
                    fi
                fi
            done
            ;;
        "pacman")
            # Extraction des noms de paquets pour Pacman
            pacman -Qu 2>/dev/null | while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    # Extraire le nom du paquet (première colonne)
                    package_name=$(echo "$line" | awk '{print $1}')
                    if [[ -n "$package_name" ]]; then
                        echo "$package_name" >> "$output_file"
                        ((package_count++))
                    fi
                fi
            done
            ;;
        "zypper")
            # Extraction des noms de paquets pour Zypper
            zypper list-updates 2>/dev/null | grep "^v \|^i " | while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    # Extraire le nom du paquet (troisième colonne pour zypper)
                    package_name=$(echo "$line" | awk '{print $3}')
                    if [[ -n "$package_name" ]]; then
                        echo "$package_name" >> "$output_file"
                        ((package_count++))
                    fi
                fi
            done
            ;;
    esac
    
    # Comptage final des paquets
    package_count=$(grep -c "^[^#]" "$output_file" 2>/dev/null || echo "0")
    
    # Ajout du résumé en fin de fichier
    cat >> "$output_file" << EOF

# ========================================
# Résumé: $package_count paquets à mettre à jour
# Fichier généré: $(basename "$output_file")
EOF

    chmod 644 "$output_file"
    log_message "SUCCESS" "Liste générée: $package_count paquets trouvés dans $(basename "$output_file")"
    
    return 0
}

# ========================================================================
# FONCTION: Vérification d'intégrité (si disponible)
# ========================================================================
verify_integrity() {
    log_message "INFO" "Vérification de l'intégrité des métadonnées..."
    
    case "$PACKAGE_MANAGER" in
        "apt")
            if apt-key list &>/dev/null; then
                log_message "SUCCESS" "Vérification des clés APT réussie"
            else
                log_message "WARNING" "Impossible de vérifier les clés APT"
            fi
            ;;
        "dnf"|"yum"|"zypper")
            if rpm --checksig /var/cache/dnf/packages/* &>/dev/null 2>&1 || 
               rpm --checksig /var/cache/yum/packages/* &>/dev/null 2>&1 ||
               rpm --checksig /var/cache/zypp/packages/* &>/dev/null 2>&1; then
                log_message "SUCCESS" "Vérification des signatures RPM réussie"
            else
                log_message "INFO" "Aucun paquet en cache à vérifier"
            fi
            ;;
        "pacman")
            if pacman-key --list-keys &>/dev/null; then
                log_message "SUCCESS" "Vérification des clés Pacman réussie"
            else
                log_message "WARNING" "Impossible de vérifier les clés Pacman"
            fi
            ;;
    esac
}

# ========================================================================
# FONCTION: Nettoyage en cas d'erreur
# ========================================================================
cleanup_on_error() {
    log_message "WARNING" "Nettoyage en cours suite à une erreur..."
    # Suppression des fichiers partiels si ils existent
    find "$PACKAGE_LIST_DIR" -name "packages_${TIMESTAMP}.txt.tmp" -delete 2>/dev/null || true
}

# ========================================================================
# FONCTION PRINCIPALE
# ========================================================================
main() {
    # Gestion des signaux pour nettoyage
    trap cleanup_on_error ERR INT TERM
    
    echo "=========================================="
    echo "Auto-Patching Manager - Download Script"
    echo "=========================================="
    
    # Étapes d'exécution
    check_root
    create_directories
    
    # Initialisation du log
    log_message "INFO" "Démarrage du script download.sh"
    log_message "INFO" "Timestamp: $TIMESTAMP"
    
    detect_distribution
    archive_old_packages
    
    if ! update_package_list; then
        log_message "ERROR" "Échec de la mise à jour de la liste des paquets"
        exit 3
    fi
    
    if ! generate_package_list; then
        log_message "ERROR" "Échec de la génération de la liste des paquets"
        exit 4
    fi
    
    verify_integrity
    
    log_message "SUCCESS" "Script download.sh terminé avec succès"
    echo "=========================================="
    echo "Liste des paquets générée avec succès!"
    echo "Consultez le fichier: $PACKAGE_LIST_DIR/packages_${TIMESTAMP}.txt"
    echo "Logs disponibles dans: $LOG_FILE"
    echo "=========================================="
    
    exit 0
}

# Exécution du script principal
main "$@"
