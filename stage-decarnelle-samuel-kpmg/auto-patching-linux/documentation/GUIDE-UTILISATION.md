# GUIDE D'UTILISATION AUTOPATCH

## Guide Complet d'Utilisation

Ce guide fournit une approche pratique et progressive pour utiliser efficacement le système AutoPatch dans différents contextes d'utilisation.

## Démarrage Rapide

### Première Utilisation (Installation Complète)

```bash
# 1. Rendre les scripts exécutables
sudo chmod +x *.sh

# 2. Première installation avec sauvegarde
sudo ./autopatch-manager.sh full-update --backup --verbose

# OU étape par étape :
# 2a. Télécharger les paquets
sudo ./download.sh --verbose

# 2b. Installer avec sauvegarde  
sudo ./install.sh --backup --verbose

# 3. Vérifier l'installation
sudo ./autopatch-manager.sh show-status
```

### Utilisation Quotidienne (Auto-Update)

```bash
# Mise à jour automatique quotidienne
sudo ./autopatch-manager.sh auto-update --enable

# Vérification manuelle des mises à jour
sudo ./autopatch-manager.sh auto-update --check

# Installation immédiate si mises à jour disponibles
sudo ./autopatch-manager.sh auto-update --install
```

## Modes d'Utilisation Détaillés

### Mode Production (Recommandé)

#### **Workflow Standard Production**

```bash
=== PHASE 1 : PLANIFICATION ===
# 1. Vérification état système avant maintenance
sudo ./autopatch-manager.sh show-status

# 2. Simulation complète sans modification
sudo ./download.sh --dry-run
sudo ./install.sh --dry-run

# 3. Validation avec équipes métiers
# → Examiner les logs de simulation
# → Valider la fenêtre de maintenance

=== PHASE 2 : PRÉPARATION ===
# 1. Téléchargement et verrouillage versions
sudo ./download.sh --verbose

# 2. Vérification contenu téléchargé
cat /var/tmp/autopatch/locked_versions.txt
cat /var/log/autopatch/download_summary*.txt

=== PHASE 3 : EXÉCUTION ===
# 1. Installation avec sauvegarde obligatoire
sudo ./install.sh --backup --verbose

# 2. Vérification post-installation
sudo ./autopatch-manager.sh show-status

=== PHASE 4 : VALIDATION ===
# 1. Tests fonctionnels applications critiques
# 2. Monitoring des services
# 3. Validation avec équipes métiers
# 4. Documentation de l'intervention
```

### Mode Test/Développement

#### **Simulations et Tests**

```bash
# 1. Tests complets sans modification système
sudo ./autopatch-manager.sh full-update --dry-run --verbose

# 2. Test de rollback sur sauvegarde existante
sudo ./rollback.sh --list-backups
sudo ./rollback.sh --restore-system backup_YYYYMMDD_HHMMSS --dry-run

# 3. Test restauration paquet spécifique
sudo ./rollback.sh --restore-package apache2 2.4.41-4ubuntu3.12 --dry-run

# 4. Génération rapports pour analyse
sudo ./rollback.sh --audit-report
```

### Mode Urgence/Récupération

#### **Procédures d'Urgence**

```bash
=== ROLLBACK SYSTÈME COMPLET ===
# 1. Accès rapide au menu interactif
sudo ./rollback.sh

# 2. Restauration automatique dernière sauvegarde
sudo ./rollback.sh --restore-system $(readlink /var/tmp/autopatch_backups/latest)

# 3. Vérification post-restauration
sudo ./autopatch-manager.sh show-status --verbose

=== ROLLBACK PAQUET CRITIQUE ===
# 1. Identification version problématique
sudo ./rollback.sh --show-versions apache2

# 2. Restauration version stable antérieure
sudo ./rollback.sh --restore-package apache2 <version_stable>

# 3. Verrouillage version restaurée
echo "apache2 hold" | sudo dpkg --set-selections  # Pour APT
```

## Workflows Recommandés par Contexte

### Environnement Entreprise

#### **Workflow Hebdomadaire**

```bash
=== LUNDI : PLANIFICATION ===
# Vérification mises à jour disponibles
sudo ./download.sh --dry-run --verbose

# Analyse impact et planning
cat /var/log/autopatch/download_summary*.txt

=== MERCREDI : SIMULATION ===  
# Simulation complète en environnement test
sudo ./autopatch-manager.sh full-update --dry-run

# Validation équipes techniques
sudo ./rollback.sh --audit-report

=== VENDREDI : DÉPLOIEMENT ===
# Exécution fenêtre de maintenance
sudo ./autopatch-manager.sh full-update --backup

# Validation post-déploiement
sudo ./autopatch-manager.sh show-status
```

#### **Workflow Automatisé**

```bash
# Configuration daemon pour exécution automatique
sudo ./autopatch-manager.sh manage-daemon --enable

# Configuration politique auto-update
sudo ./autopatch-manager.sh manage-daemon --configure

# Monitoring via crontab
0 6 * * 1 /usr/local/bin/autopatch-manager.sh auto-update --check
0 2 * * 0 /usr/local/bin/autopatch-manager.sh auto-update --install --backup
```

### Environnement Personnel/Small Business

#### **Workflow Simplifié**

```bash
# Installation mensuelle avec sauvegarde
sudo ./autopatch-manager.sh full-update --backup

# Vérification hebdomadaire des mises à jour
sudo ./autopatch-manager.sh auto-update --check

# Maintenance trimestrielle
sudo ./rollback.sh --cleanup-backups --days 90
```

### Environnement Serveur/Cloud

#### **Workflow Infrastructure**

```bash
=== INTÉGRATION CI/CD ===
# Pipeline de test automatisé
./autopatch-manager.sh full-update --dry-run --verbose > autopatch-test.log

# Déploiement conditionnel selon tests
if [ $? -eq 0 ]; then
    ./autopatch-manager.sh full-update --backup
fi

=== ORCHESTRATION KUBERNETES/DOCKER ===
# Script intégration container
#!/bin/bash
kubectl drain node-target
/usr/local/bin/autopatch-manager.sh full-update --backup
kubectl uncordon node-target

=== MONITORING INFRASTRUCTURE ===
# Intégration Prometheus/Grafana
curl -X POST http://monitoring:9091/metrics/job/autopatch \
     --data-binary @<(./autopatch-manager.sh show-status --format=prometheus)
```

## Gestion des Logs et Monitoring

### Centralisation des Logs

```bash
=== STRUCTURE LOGS AUTOPATCH ===
/var/log/autopatch/
├── autopatch-manager.log          # Manager principal
├── download.log                   # Téléchargements
├── install.log                    # Installations  
├── rollback.log                   # Opérations rollback
├── summary_files/                 # Résumés détaillés
│   ├── download_summary_*.txt
│   ├── install_summary_*.txt
│   └── rollback_report_*.txt
└── daemon/                        # Logs daemon systemd
    ├── autopatch-daemon.log
    └── autopatch-scheduler.log

=== COMMANDES MONITORING ===
# Surveillance en temps réel
sudo tail -f /var/log/autopatch/autopatch-manager.log

# Analyse des dernières opérations
sudo grep "ERROR\|WARN" /var/log/autopatch/*.log | tail -20

# Statistiques d'utilisation
sudo find /var/log/autopatch -name "*summary*" -exec basename {} \; | sort
```

### Intégration Monitoring Externe

#### **Syslog Integration**

```bash
# Configuration rsyslog pour centralisation
echo "local0.*  @@monitoring-server:514" | sudo tee -a /etc/rsyslog.conf

# Redirection logs autopatch vers syslog
logger -p local0.info -t autopatch "$(cat /var/log/autopatch/autopatch-manager.log | tail -1)"
```

#### **Metrics Collection**

```bash
# Script collecte métriques personnalisé
#!/bin/bash
# autopatch-metrics.sh

# Métriques de base
total_backups=$(find /var/tmp/autopatch_backups -name "backup_*" -type d | wc -l)
last_update=$(stat -c %Y /var/log/autopatch/install.log 2>/dev/null || echo "0")
system_packages=$(dpkg -l | grep "^ii" | wc -l)  # Pour APT

# Format Prometheus
echo "autopatch_backups_total $total_backups"
echo "autopatch_last_update_timestamp $last_update"  
echo "autopatch_system_packages_total $system_packages"
```

## Résolution de Problèmes Courants

### Problèmes Fréquents et Solutions

#### **Erreur : "Versions non autorisées détectées"**

```bash
SYMPTÔME: 
SÉCURITÉ COMPROMISE : Versions non autorisées détectées!

DIAGNOSTIC:
sudo cat /var/tmp/autopatch/locked_versions.txt
sudo ls -la /var/tmp/autopatch/packages/

SOLUTION:
# 1. Nettoyer le cache de téléchargement
sudo rm -rf /var/tmp/autopatch/packages/*

# 2. Re-télécharger avec versions cohérentes
sudo ./download.sh --force --verbose

# 3. Vérifier cohérence avant installation
sudo ./install.sh --dry-run
```

#### **Erreur : "Sauvegarde impossible"**

```bash
SYMPTÔME:
Échec de la création de sauvegarde (espace, permissions, etc.)

DIAGNOSTIC:
df -h /var/tmp                    # Vérifier espace disque
ls -la /var/tmp/autopatch_backups # Vérifier permissions

SOLUTION:
# 1. Libérer de l'espace si nécessaire
sudo ./rollback.sh --cleanup-backups --days 30

# 2. Corriger les permissions  
sudo mkdir -p /var/tmp/autopatch_backups
sudo chown root:root /var/tmp/autopatch_backups
sudo chmod 755 /var/tmp/autopatch_backups

# 3. Réessayer avec force
sudo ./install.sh --backup --force
```

#### **Erreur : "Lock file existe"**

```bash
SYMPTÔME:
Une instance d'autopatch est déjà en cours d'exécution

DIAGNOSTIC:
ls -la /tmp/autopatch*.lock

SOLUTION:
# 1. Vérifier processus réellement actif
ps aux | grep autopatch

# 2. Si aucun processus, supprimer lock manuellement
sudo rm -f /tmp/autopatch*.lock

# 3. Redémarrer opération
sudo ./autopatch-manager.sh full-update
```

#### **Erreur : "Dépendances non résolues"**

```bash
SYMPTÔME:
Certains paquets ont des dépendances non satisfaites

SOLUTION APT:
sudo apt-get -f install          # Résolution automatique
sudo dpkg --configure -a         # Configuration paquets en attente

SOLUTION DNF/YUM:
sudo dnf check                    # Diagnostic dépendances
sudo dnf autoremove               # Nettoyage paquets orphelins

SOLUTION PACMAN:
sudo pacman -Syu --noconfirm      # Synchronisation complète
sudo pacman -Rns $(pacman -Qtdq) 2>/dev/null || true  # Nettoyage orphelins
```

### Outils de Debug Avancés

#### **Script de Diagnostic Complet**

```bash
#!/bin/bash
# autopatch-debug.sh - Script diagnostic complet

echo "=== DIAGNOSTIC AUTOPATCH COMPLET ==="
echo "Date: $(date)"
echo ""

echo "=== ENVIRONNEMENT SYSTÈME ==="
echo "Distribution: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo ""

echo "=== ESPACE DISQUE ==="
df -h / /tmp /var/tmp 2>/dev/null | grep -v "Filesystem"
echo ""

echo "=== PERMISSIONS AUTOPATCH ==="
ls -la /usr/local/bin/autopatch*.sh 2>/dev/null || echo "Scripts non installés dans /usr/local/bin"
ls -la /var/log/autopatch/ 2>/dev/null || echo "Répertoire logs manquant"
ls -la /var/tmp/autopatch/ 2>/dev/null || echo "Répertoire travail manquant"
ls -la /var/tmp/autopatch_backups/ 2>/dev/null || echo "Répertoire sauvegardes manquant"
echo ""

echo "=== PROCESSUS ACTIFS ==="
ps aux | grep autopatch | grep -v grep || echo "Aucun processus autopatch actif"
echo ""

echo "=== LOCKS ACTIFS ==="
ls -la /tmp/autopatch*.lock 2>/dev/null || echo "Aucun lock actif"
echo ""

echo "=== DERNIÈRES OPÉRATIONS ==="
if [[ -f /var/log/autopatch/autopatch-manager.log ]]; then
    echo "Dernières lignes manager.log:"
    tail -5 /var/log/autopatch/autopatch-manager.log
else
    echo "Aucun log manager trouvé"
fi
echo ""

echo "=== ÉTAT GESTIONNAIRE PAQUETS ==="
if command -v apt-get >/dev/null 2>&1; then
    echo "APT - Processus actifs:"
    ps aux | grep apt | grep -v grep || echo "Aucun processus APT actif"
elif command -v dnf >/dev/null 2>&1; then
    echo "DNF - Processus actifs:"
    ps aux | grep dnf | grep -v grep || echo "Aucun processus DNF actif"
elif command -v pacman >/dev/null 2>&1; then
    echo "PACMAN - Processus actifs:"
    ps aux | grep pacman | grep -v grep || echo "Aucun processus Pacman actif"
fi
echo ""

echo "=== CONFIGURATION DAEMON ==="
systemctl status autopatch-daemon.service 2>/dev/null || echo "Service daemon non configuré"
echo ""

echo "=== FIN DIAGNOSTIC ==="
```

## Ressources et Documentation

### Documentation de Référence

```bash
=== AIDE INTÉGRÉE ===
sudo ./autopatch-manager.sh --help    # Aide manager principal
sudo ./download.sh --help             # Aide téléchargement
sudo ./install.sh --help              # Aide installation
sudo ./rollback.sh --help             # Aide rollback

=== DOCUMENTATION COMPLÈTE ===
/path/to/documentation/
├── README.md                     # Index documentation
├── ARCHITECTURE-GENERALE.md     # Vue d'ensemble système
├── DOCUMENTATION-MANAGER.md     # Manager détaillé  
├── DOCUMENTATION-DOWNLOAD.md    # Download détaillé
├── DOCUMENTATION-INSTALL.md     # Install détaillé
├── DOCUMENTATION-ROLLBACK.md    # Rollback détaillé
├── GUIDE-UTILISATION.md          # Ce guide
├── GUIDE-SECURITE.md             # Guide sécurité
└── WORKFLOWS.md                  # Workflows spécialisés
```

### Formation Équipes

#### **Check-list Formation Administrateurs**

```bash
NIVEAU DÉBUTANT:
□ Comprendre l'architecture générale AutoPatch
□ Maîtriser le mode interactif des scripts
□ Savoir créer et restaurer une sauvegarde
□ Connaître les commandes de diagnostic de base
□ Comprendre les logs et leur utilisation

NIVEAU INTERMÉDIAIRE:
□ Maîtriser tous les modes en ligne de commande
□ Configurer et gérer le daemon systemd
□ Intégrer AutoPatch dans scripts automatisés
□ Diagnostiquer et résoudre problèmes courants
□ Personnaliser politiques de sauvegarde

NIVEAU AVANCÉ:
□ Développer workflows personnalisés
□ Intégrer monitoring et métriques externes
□ Optimiser performance et ressources
□ Contribuer améliorations code source
□ Former autres administrateurs
```

---

**Auteur** : DECARNELLE Samuel  
**Version** : 1.0  
**Date** : 2025-07-22

> Ce guide d'utilisation couvre les scénarios pratiques les plus courants et fournit des workflows éprouvés pour une utilisation efficace et sécurisée d'AutoPatch dans tous les environnements.
