# DOCUMENTATION SYSTÈME AUTOPATCH

Cette documentation complète décrit l'architecture, le fonctionnement et l'utilisation du système AutoPatch - une solution sécurisée de gestion automatisée des mises à jour système Linux.

## Table des Matières

### Architecture Générale
- **[ARCHITECTURE-GENERALE.md](./ARCHITECTURE-GENERALE.md)** - Vue d'ensemble du système et schémas architecturaux

### Documentation des Scripts Individuels
- **[DOCUMENTATION-MANAGER.md](./DOCUMENTATION-MANAGER.md)** - Script orchestrateur central
- **[DOCUMENTATION-DOWNLOAD.md](./DOCUMENTATION-DOWNLOAD.md)** - Script de téléchargement sécurisé
- **[DOCUMENTATION-INSTALL.md](./DOCUMENTATION-INSTALL.md)** - Script d'installation avec contrôle des versions
- **[DOCUMENTATION-ROLLBACK.md](./DOCUMENTATION-ROLLBACK.md)** - Script de sauvegarde et restauration

### Guides d'Utilisation
- **[GUIDE-UTILISATION.md](./GUIDE-UTILISATION.md)** - Guide complet d'utilisation pratique
- **[GUIDE-SECURITE.md](./GUIDE-SECURITE.md)** - Mécanismes de sécurité et verrouillage des versions

### Flux de Travail et Processus
- **[WORKFLOWS.md](./WORKFLOWS.md)** - Diagrammes de flux et processus détaillés

## Vue d'Ensemble Rapide

Le système AutoPatch est composé de **4 scripts principaux** qui fonctionnent en synergie :

### `autopatch-manager.sh` - L'Orchestrateur
- **Rôle** : Coordinateur central et interface unifiée
- **Fonctions** : Gestion des démons systemd, transmission des options, contrôle de l'intégrité
- **Usage** : `sudo ./autopatch-manager.sh [COMMAND] [OPTIONS]`

### `download.sh` - Le Téléchargeur Sécurisé
- **Rôle** : Téléchargement des paquets avec verrouillage des versions
- **Fonctions** : Détection distribution, téléchargement, génération de fichiers de contrôle
- **Sécurité** : Création de `locked_versions.txt` et archivage historique

### `install.sh` - L'Installateur Contrôlé
- **Rôle** : Installation exclusive des versions approuvées
- **Fonctions** : Vérification des versions, installation sécurisée, sauvegarde optionnelle
- **Sécurité** : Refuse toute version non verrouillée préalablement

### `rollback.sh` - Le Gestionnaire de Sauvegardes
- **Rôle** : Sauvegarde système complète et restauration
- **Fonctions** : Menu interactif, gestion des sauvegardes, rollback vers versions historiques
- **Capacités** : Restauration système complète ou vers versions de paquets spécifiques

## Principes de Sécurité

### Verrouillage des Versions
Le système garantit qu'**aucune version non approuvée** ne peut être installée :

```bash
# Lundi : Téléchargement + Verrouillage
sudo ./autopatch-manager.sh download
# → Génère locked_versions.txt avec apache=2.4.1, nginx=1.20.2, etc.

# Mercredi : Installation UNIQUEMENT des versions verrouillées
sudo ./autopatch-manager.sh install
# → Même si apache 2.4.2 est disponible, installe SEULEMENT apache 2.4.1
```

### Historique et Rollback
- **Conservation automatique** des 5 dernières versions
- **Rollback système complet** vers un point de restauration
- **Rollback sélectif** vers des versions de paquets spécifiques

## Démarrage Rapide

### Installation et Configuration
```bash
# 1. Configuration initiale
sudo ./autopatch-manager.sh setup

# 2. Premier téléchargement
sudo ./autopatch-manager.sh download --verbose

# 3. Installation avec sauvegarde
sudo ./autopatch-manager.sh install --backup --verbose

# 4. Vérification du statut
sudo ./autopatch-manager.sh status
```

### Automatisation avec Démons systemd
```bash
# Configuration des démons
sudo ./autopatch-manager.sh daemon config

# Création des services
sudo ./autopatch-manager.sh daemon create

# Activation de l'automatisation
sudo ./autopatch-manager.sh daemon enable
```

## Distributions Supportées

| Distribution | Gestionnaire | Status | Commandes |
|-------------|-------------|--------|-----------|
| **Debian/Ubuntu** | APT | Complet | `apt-get`, `dpkg` |
| **CentOS/RHEL** | YUM/DNF | Complet | `yum`, `dnf`, `rpm` |
| **Fedora** | DNF | Complet | `dnf`, `rpm` |
| **Arch Linux** | Pacman | Complet | `pacman` |

## Cas d'Usage Typiques

### Environnement d'Entreprise
```bash
# Workflow hebdomadaire automatisé
# Lundi 02h00 : Téléchargement automatique
# Mercredi 02h30 : Installation automatique avec sauvegarde
sudo ./autopatch-manager.sh daemon enable
```

### Gestion Manuelle
```bash
# Contrôle total du processus
sudo ./autopatch-manager.sh download         # Téléchargement
sudo ./autopatch-manager.sh install --backup # Installation + sauvegarde
sudo ./autopatch-manager.sh rollback save    # Sauvegarde additionnelle
```

### Situations d'Urgence
```bash
# Rollback rapide après problème
sudo ./autopatch-manager.sh rollback         # Menu interactif
# OU directement
sudo ./autopatch-manager.sh rollback restore backup_20240722_143000
```

## Structure des Fichiers

```
test-auto-patching-linux/
├── autopatch-manager.sh           # Script orchestrateur principal
├── autopatch-scripts/             # Répertoire des sous-scripts
│   ├── download.sh               # Script de téléchargement
│   ├── install.sh                # Script d'installation
│   └── rollback.sh               # Script de sauvegarde/restauration
├── documentation/                # Documentation complète
│   ├── README.md                 # Ce fichier
│   ├── ARCHITECTURE-GENERALE.md  # Vue d'ensemble architectural
│   ├── DOCUMENTATION-*.md        # Docs spécifiques par script
│   ├── GUIDE-*.md               # Guides d'utilisation
│   └── WORKFLOWS.md             # Diagrammes de flux
└── /var/tmp/autopatch_*/         # Répertoires de travail (créés à l'exécution)
    ├── autopatch_downloads/      # Paquets téléchargés
    ├── autopatch_backups/        # Sauvegardes système
    └── /var/log/autopatch/       # Logs détaillés
```

## Prérequis et Recommandations

### Prérequis Système
- **OS** : Linux (Debian/Ubuntu, CentOS/RHEL/Fedora, Arch)
- **Privilèges** : root (sudo)
- **Espace disque** : Min. 2GB libre pour téléchargements/sauvegardes
- **Réseau** : Accès aux dépôts de paquets

### Recommandations
- **Testez d'abord** sur un environnement de développement
- **Utilisez --dry-run** pour simuler avant exécution réelle
- **Planifiez les sauvegardes** avant les installations importantes
- **Surveillez les logs** pour détecter les anomalies

## Support et Maintenance

### Logs et Diagnostics
```bash
# Logs centralisés
tail -f /var/log/autopatch/manager.log
tail -f /var/log/autopatch/download.log
tail -f /var/log/autopatch/install.log
tail -f /var/log/autopatch/rollback.log
```

### Vérification de l'Intégrité
```bash
# Vérification complète du système
sudo ./autopatch-manager.sh check
sudo ./autopatch-manager.sh status
```

---

**Auteur** : DECARNELLE Samuel  
**Version** : 1.0  
**Date** : 2025-07-22

> **Conseil** : Commencez par lire [ARCHITECTURE-GENERALE.md](./ARCHITECTURE-GENERALE.md) pour comprendre les concepts fondamentaux, puis consultez les guides spécifiques selon vos besoins.
