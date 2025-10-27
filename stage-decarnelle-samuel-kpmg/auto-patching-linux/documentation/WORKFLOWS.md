# WORKFLOWS SPÉCIALISÉS AUTOPATCH

## Workflows Spécialisés par Contexte

Ce document présente des workflows spécialisés et des cas d'usage avancés d'AutoPatch pour différents environnements et besoins métiers spécifiques.

## Workflows Entreprise

### Workflow DevOps/CI-CD Integration

#### **Pipeline Jenkins Integration**

```bash
=== JENKINSFILE AUTOPATCH ===
pipeline {
    agent any
    
    parameters {
        booleanParam(name: 'DRY_RUN', defaultValue: true, description: 'Mode simulation')
        booleanParam(name: 'FORCE_BACKUP', defaultValue: true, description: 'Sauvegarde forcée')
        choice(name: 'TARGET_ENV', choices: ['dev', 'staging', 'prod'], description: 'Environnement cible')
    }
    
    environment {
        AUTOPATCH_HOME = '/usr/local/bin'
        NOTIFICATION_SLACK = credentials('slack-webhook-url')
        BACKUP_RETENTION_DAYS = '30'
    }
    
    stages {
        stage('Pre-Flight Checks') {
            steps {
                script {
                    // Vérification état système
                    sh "${AUTOPATCH_HOME}/autopatch-manager.sh show-status --format=json > system-status.json"
                    
                    // Analyse espace disque
                    sh "df -h | grep -E '(/$|/var|/tmp)' > disk-status.txt"
                    
                    // Validation environnement
                    sh """
                    if [[ \$(df /var/tmp | tail -1 | awk '{print \$5}' | sed 's/%//') -gt 80 ]]; then
                        echo "ERREUR: Espace disque insuffisant"
                        exit 1
                    fi
                    """
                }
            }
        }
        
        stage('Package Download & Verification') {
            steps {
                script {
                    def dryRunFlag = params.DRY_RUN ? '--dry-run' : ''
                    
                    sh "${AUTOPATCH_HOME}/download.sh ${dryRunFlag} --verbose"
                    
                    // Archivage des résultats
                    archiveArtifacts artifacts: '/var/log/autopatch/download_summary_*.txt', 
                                   fingerprint: true
                    
                    // Validation packages critiques
                    sh '''
                    if grep -q "apache2\\|nginx\\|mysql\\|postgresql" /var/tmp/autopatch/packages_to_install.log; then
                        echo "ATTENTION: Paquets critiques détectés, validation manuelle requise"
                        # Notification équipe
                        curl -X POST -H 'Content-type: application/json' \
                             --data '{"text":"AutoPatch: Paquets critiques détectés - Validation requise"}' \
                             $NOTIFICATION_SLACK
                    fi
                    '''
                }
            }
        }
        
        stage('Security Validation') {
            steps {
                script {
                    // Validation signatures et intégrité
                    sh '''
                    cd /var/tmp/autopatch
                    
                    # Vérification locked_versions.txt
                    if [[ ! -f locked_versions.txt ]]; then
                        echo "ERREUR SÉCURITÉ: Fichier versions verrouillées manquant"
                        exit 1
                    fi
                    
                    # Audit sécurité automatique
                    ${AUTOPATCH_HOME}/rollback.sh --audit-report --format=json > security-audit.json
                    '''
                    
                    // Publication résultats sécurité
                    publishHTML([
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: '/var/tmp/autopatch',
                        reportFiles: 'security-audit.json',
                        reportName: 'Security Audit Report'
                    ])
                }
            }
        }
        
        stage('Deployment Approval') {
            when {
                allOf {
                    not { params.DRY_RUN }
                    environment name: 'TARGET_ENV', value: 'prod'
                }
            }
            steps {
                script {
                    // Demande approbation pour production
                    def approval = input message: 'Autoriser déploiement production?',
                                        ok: 'Déployer',
                                        parameters: [
                                            booleanParam(defaultValue: true, 
                                                       description: 'Créer sauvegarde complète', 
                                                       name: 'CREATE_BACKUP')
                                        ]
                    
                    env.CREATE_BACKUP = approval.toString()
                }
            }
        }
        
        stage('Package Installation') {
            steps {
                script {
                    def backupFlag = (params.FORCE_BACKUP || env.CREATE_BACKUP == 'true') ? '--backup' : ''
                    def dryRunFlag = params.DRY_RUN ? '--dry-run' : ''
                    
                    sh "${AUTOPATCH_HOME}/install.sh ${backupFlag} ${dryRunFlag} --verbose"
                    
                    // Archivage résultats installation
                    archiveArtifacts artifacts: '/var/log/autopatch/install_summary_*.txt',
                                   fingerprint: true
                }
            }
        }
        
        stage('Post-Installation Validation') {
            steps {
                script {
                    // Tests fonctionnels post-installation
                    sh '''
                    # Vérification services critiques
                    systemctl is-active apache2 || echo "Apache2 inactif"
                    systemctl is-active nginx || echo "Nginx inactif"  
                    systemctl is-active mysql || echo "MySQL inactif"
                    
                    # Tests connectivité applicative
                    curl -f http://localhost/health-check || echo "Health check échoué"
                    
                    # Génération rapport final
                    ${AUTOPATCH_HOME}/autopatch-manager.sh show-status --detailed > final-status-report.txt
                    '''
                    
                    archiveArtifacts artifacts: 'final-status-report.txt', fingerprint: true
                }
            }
        }
    }
    
    post {
        always {
            // Nettoyage et archivage
            script {
                // Copie logs pour archivage Jenkins
                sh 'cp /var/log/autopatch/*.log . 2>/dev/null || true'
                archiveArtifacts artifacts: '*.log', allowEmptyArchive: true
                
                // Nettoyage répertoires temporaires
                sh 'rm -f *.json *.txt *.log 2>/dev/null || true'
            }
        }
        
        success {
            script {
                def message = params.DRY_RUN ? 
                    "AutoPatch simulation réussie (${params.TARGET_ENV})" :
                    "AutoPatch déploiement réussi (${params.TARGET_ENV})"
                
                sh """
                curl -X POST -H 'Content-type: application/json' \
                     --data '{"text":"${message}"}' \
                     $NOTIFICATION_SLACK
                """
            }
        }
        
        failure {
            script {
                sh """
                curl -X POST -H 'Content-type: application/json' \
                     --data '{"text":"AutoPatch ÉCHEC - ${params.TARGET_ENV} - Vérification requise"}' \
                     $NOTIFICATION_SLACK
                """
                
                // Rollback automatique en cas d'échec en production
                if (!params.DRY_RUN && params.TARGET_ENV == 'prod') {
                    sh '''
                    echo "Rollback automatique initié..."
                    ${AUTOPATCH_HOME}/rollback.sh --restore-system \$(readlink /var/tmp/autopatch_backups/latest) --force
                    '''
                }
            }
        }
    }
}
```

#### **Integration Docker/Kubernetes**

```bash
=== DOCKERFILE AUTOPATCH-ENABLED ===
FROM ubuntu:22.04

# Installation AutoPatch dans container
RUN apt-get update && apt-get install -y \
    curl wget gpg sudo systemctl \
    && rm -rf /var/lib/apt/lists/*

# Copie scripts AutoPatch
COPY autopatch-*.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/autopatch-*.sh

# Configuration environnement
ENV AUTOPATCH_HOME=/usr/local/bin
ENV AUTOPATCH_LOG_LEVEL=INFO
ENV AUTOPATCH_BACKUP_ENABLED=true

# Point d'entrée avec AutoPatch
COPY entrypoint-autopatch.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

=== ENTRYPOINT SCRIPT ===
#!/bin/bash
# entrypoint-autopatch.sh

echo "Initialisation container avec AutoPatch..."

# Vérification santé système
/usr/local/bin/autopatch-manager.sh show-status

# Auto-update conditionnel
if [[ "$AUTOPATCH_AUTO_UPDATE" == "true" ]]; then
    echo "Auto-update activé..."
    /usr/local/bin/autopatch-manager.sh auto-update --install --backup
fi

# Démarrage application
exec "$@"

=== KUBERNETES DEPLOYMENT ===
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-autopatch
  namespace: production
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: myapp-autopatch
  template:
    metadata:
      labels:
        app: myapp-autopatch
    spec:
      initContainers:
      - name: autopatch-init
        image: myapp:autopatch-latest
        command: ['/usr/local/bin/autopatch-manager.sh']
        args: ['full-update', '--backup', '--dry-run']
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
        volumeMounts:
        - name: autopatch-logs
          mountPath: /var/log/autopatch
      containers:
      - name: myapp
        image: myapp:autopatch-latest
        env:
        - name: AUTOPATCH_AUTO_UPDATE
          value: "false"
        - name: AUTOPATCH_BACKUP_ENABLED
          value: "true"
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        volumeMounts:
        - name: autopatch-logs
          mountPath: /var/log/autopatch
        - name: autopatch-backups
          mountPath: /var/tmp/autopatch_backups
      volumes:
      - name: autopatch-logs
        persistentVolumeClaim:
          claimName: autopatch-logs-pvc
      - name: autopatch-backups
        persistentVolumeClaim:
          claimName: autopatch-backups-pvc
```

### Workflow Disaster Recovery

#### **Plan de Continuité avec AutoPatch**

```bash
=== DISASTER RECOVERY PLAN ===
#!/bin/bash
# dr-autopatch-plan.sh

disaster_recovery_autopatch() {
    local disaster_type="$1"  # hardware_failure, data_corruption, security_breach
    local recovery_mode="$2"  # minimal, standard, complete
    
    echo "PLAN DE CONTINUITÉ ACTIVÉ"
    echo "Type: $disaster_type | Mode: $recovery_mode"
    echo "Timestamp: $(date)"
    
    case "$disaster_type" in
        hardware_failure)
            hardware_failure_recovery "$recovery_mode"
            ;;
        data_corruption)
            data_corruption_recovery "$recovery_mode"
            ;;
        security_breach)
            security_breach_recovery "$recovery_mode"
            ;;
        *)
            generic_disaster_recovery "$recovery_mode"
            ;;
    esac
}

hardware_failure_recovery() {
    local mode="$1"
    
    echo "RÉCUPÉRATION PANNE MATÉRIEL - Mode: $mode"
    
    # Phase 1: Évaluation dommages
    echo "Phase 1: Évaluation état système..."
    /usr/local/bin/autopatch-manager.sh show-status --detailed > disaster-assessment.log
    
    # Phase 2: Récupération sauvegardes critiques
    echo "Phase 2: Récupération sauvegardes..."
    if [[ -d /var/tmp/autopatch_backups ]]; then
        # Identification dernière sauvegarde valide
        local latest_backup=$(/usr/local/bin/rollback.sh --list-backups | grep "backup_" | tail -1 | awk '{print $2}')
        
        if [[ -n "$latest_backup" ]]; then
            echo "Sauvegarde trouvée: $latest_backup"
            
            case "$mode" in
                minimal)
                    # Restauration services critiques uniquement
                    restore_critical_services_only "$latest_backup"
                    ;;
                standard|complete)
                    # Restauration système complète
                    /usr/local/bin/rollback.sh --restore-system "$latest_backup" --force
                    ;;
            esac
        else
            echo "CRITIQUE: Aucune sauvegarde valide trouvée"
            initiate_manual_recovery
        fi
    fi
    
    # Phase 3: Validation fonctionnelle
    echo "Phase 3: Validation fonctionnelle..."
    post_recovery_validation "$mode"
}

data_corruption_recovery() {
    local mode="$1"
    
    echo "RÉCUPÉRATION CORRUPTION DONNÉES - Mode: $mode"
    
    # Isolation système corrompu
    echo "Isolation système..."
    systemctl stop apache2 nginx mysql postgresql 2>/dev/null || true
    
    # Analyse intégrité
    echo "Analyse intégrité..."
    /usr/local/bin/rollback.sh --verify-system > integrity-report.log
    
    # Restauration données depuis sauvegarde
    echo "Restauration données..."
    restore_from_clean_backup "$mode"
    
    # Reconstruction index et caches
    echo "Reconstruction index..."
    rebuild_system_indexes
}

security_breach_recovery() {
    local mode="$1"
    
    echo "RÉCUPÉRATION VIOLATION SÉCURITÉ - Mode: $mode"
    
    # Lockdown immédiat
    echo "Lockdown sécurité..."
    /usr/local/bin/autopatch-manager.sh emergency-lockdown --full
    
    # Audit forensique
    echo "Audit forensique..."
    generate_forensic_report
    
    # Reconstruction environnement sain
    echo "Reconstruction sécurisée..."
    rebuild_secure_environment "$mode"
    
    # Durcissement post-incident
    echo "Durcissement sécurité..."
    apply_post_incident_hardening
}

=== AUTOMATED BACKUP REPLICATION ===
#!/bin/bash
# backup-replication.sh

replicate_backups_to_dr_site() {
    local dr_server="$1"
    local dr_path="$2"
    
    echo "Réplication sauvegardes vers site DR..."
    
    # Synchronisation sauvegardes
    rsync -avz --delete \
          --exclude="*.tmp" \
          /var/tmp/autopatch_backups/ \
          "$dr_server:$dr_path/"
    
    # Validation intégrité post-réplication
    ssh "$dr_server" "find $dr_path -name 'backup_*' -type d | xargs -I {} /usr/local/bin/rollback.sh --validate-backup {}"
    
    # Test restauration périodique
    if [[ "$(date +%u)" == "7" ]]; then  # Dimanche
        echo "Test restauration hebdomadaire..."
        ssh "$dr_server" "/usr/local/bin/rollback.sh --restore-test --latest-backup"
    fi
}

# Crontab pour réplication automatique
# 0 */6 * * * /usr/local/bin/backup-replication.sh dr-server.local /backup/autopatch
```

## Workflows Cloud et Infrastructure

### AWS Integration

#### **CloudWatch Integration**

```bash
=== CLOUDWATCH METRICS PUBLISHER ===
#!/bin/bash
# publish-cloudwatch-metrics.sh

publish_autopatch_metrics() {
    local namespace="AutoPatch/Operations"
    local instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    local region=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    
    # Métriques opérationnelles
    local total_packages=$(dpkg -l | grep "^ii" | wc -l)
    local backup_count=$(find /var/tmp/autopatch_backups -name "backup_*" -type d | wc -l)
    local disk_usage=$(df /var/tmp | tail -1 | awk '{print $5}' | sed 's/%//')
    
    # Publication CloudWatch
    aws cloudwatch put-metric-data \
        --namespace "$namespace" \
        --region "$region" \
        --metric-data \
            MetricName=TotalPackages,Value=$total_packages,Unit=Count,Dimensions=InstanceId=$instance_id \
            MetricName=BackupCount,Value=$backup_count,Unit=Count,Dimensions=InstanceId=$instance_id \
            MetricName=DiskUsagePercent,Value=$disk_usage,Unit=Percent,Dimensions=InstanceId=$instance_id
    
    # Métriques de sécurité
    local security_violations=$(grep -c "SÉCURITÉ COMPROMISE" /var/log/autopatch/*.log || echo "0")
    
    aws cloudwatch put-metric-data \
        --namespace "$namespace/Security" \
        --region "$region" \
        --metric-data \
            MetricName=SecurityViolations,Value=$security_violations,Unit=Count,Dimensions=InstanceId=$instance_id
}

=== LAMBDA FUNCTION FOR AUTOMATION ===
import json
import boto3
import subprocess

def lambda_handler(event, context):
    """
    Lambda pour orchestration AutoPatch multi-instances
    """
    
    # Configuration
    ssm_client = boto3.client('ssm')
    sns_client = boto3.client('sns')
    
    instance_ids = event.get('instance_ids', [])
    operation = event.get('operation', 'auto-update')
    
    # Commandes AutoPatch selon opération
    commands = {
        'auto-update': ['/usr/local/bin/autopatch-manager.sh auto-update --install --backup'],
        'full-update': ['/usr/local/bin/autopatch-manager.sh full-update --backup'],
        'rollback': ['/usr/local/bin/rollback.sh --restore-system $(readlink /var/tmp/autopatch_backups/latest)']
    }
    
    if operation not in commands:
        return {
            'statusCode': 400,
            'body': json.dumps(f'Opération non supportée: {operation}')
        }
    
    try:
        # Exécution commande via SSM
        response = ssm_client.send_command(
            InstanceIds=instance_ids,
            DocumentName='AWS-RunShellScript',
            Parameters={
                'commands': commands[operation],
                'timeoutSeconds': ['3600']
            },
            TimeoutSeconds=3600,
            MaxConcurrency='50%',
            MaxErrors='1'
        )
        
        command_id = response['Command']['CommandId']
        
        # Notification SNS
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'AutoPatch {operation} initiated',
            Message=f'Command ID: {command_id}\nInstances: {instance_ids}'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'command_id': command_id,
                'instances': instance_ids,
                'operation': operation
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps(f'Erreur: {str(e)}')
        }
```

#### **Auto Scaling Group Integration**

```bash
=== ASG LIFECYCLE HOOKS ===
#!/bin/bash
# asg-autopatch-lifecycle.sh

handle_asg_lifecycle() {
    local lifecycle_action="$1"  # LAUNCH, TERMINATE
    local instance_id="$2"
    local auto_scaling_group="$3"
    local lifecycle_hook_name="$4"
    
    case "$lifecycle_action" in
        LAUNCH)
            echo "Nouvelle instance ASG: $instance_id"
            
            # Attente stabilisation système
            sleep 60
            
            # Installation et configuration AutoPatch
            /usr/local/bin/autopatch-manager.sh install --configure
            
            # Première synchronisation
            /usr/local/bin/autopatch-manager.sh auto-update --check
            
            # Enregistrement monitoring
            publish_autopatch_metrics
            
            # Finalisation lifecycle
            aws autoscaling complete-lifecycle-action \
                --lifecycle-action-result CONTINUE \
                --lifecycle-hook-name "$lifecycle_hook_name" \
                --auto-scaling-group-name "$auto_scaling_group" \
                --instance-id "$instance_id"
            ;;
            
        TERMINATE)
            echo "Terminaison instance ASG: $instance_id"
            
            # Sauvegarde finale
            /usr/local/bin/install.sh --backup --force
            
            # Upload sauvegarde S3
            aws s3 sync /var/tmp/autopatch_backups/ \
                s3://autopatch-backups-bucket/$instance_id/ \
                --exclude="*" --include="backup_*"
            
            # Finalisation lifecycle
            aws autoscaling complete-lifecycle-action \
                --lifecycle-action-result CONTINUE \
                --lifecycle-hook-name "$lifecycle_hook_name" \
                --auto-scaling-group-name "$auto_scaling_group" \
                --instance-id "$instance_id"
            ;;
    esac
}

=== USER DATA SCRIPT ===
#!/bin/bash
# Instance UserData avec AutoPatch

# Installation AutoPatch
cd /tmp
wget https://releases.autopatch.local/latest/autopatch-bundle.tar.gz
tar xzf autopatch-bundle.tar.gz
sudo cp autopatch-*.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/autopatch-*.sh

# Configuration environnement AWS
echo 'export AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)' >> /etc/environment
echo 'export INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)' >> /etc/environment

# Configuration AutoPatch
sudo /usr/local/bin/autopatch-manager.sh manage-daemon --install --enable

# Tags CloudWatch
aws ec2 create-tags \
    --resources $(curl -s http://169.254.169.254/latest/meta-data/instance-id) \
    --tags Key=AutoPatchEnabled,Value=true Key=AutoPatchVersion,Value=1.0
```

### Docker Swarm / Stack Integration

#### **Service Update Strategy**

```bash
=== SWARM SERVICE UPDATE ===
#!/bin/bash
# swarm-autopatch-update.sh

update_swarm_service_with_autopatch() {
    local service_name="$1"
    local update_strategy="$2"  # rolling, parallel, manual
    
    echo "Mise à jour Swarm Service: $service_name"
    
    case "$update_strategy" in
        rolling)
            # Mise à jour progressive avec AutoPatch
            docker service update \
                --update-parallelism 1 \
                --update-delay 30s \
                --update-failure-action rollback \
                --env-add AUTOPATCH_AUTO_UPDATE=true \
                --env-add AUTOPATCH_BACKUP_ENABLED=true \
                "$service_name"
            ;;
            
        parallel)
            # Mise à jour parallèle contrôlée
            docker service update \
                --update-parallelism 3 \
                --update-delay 10s \
                --update-failure-action pause \
                --env-add AUTOPATCH_AUTO_UPDATE=true \
                "$service_name"
            ;;
            
        manual)
            # Mise à jour manuelle avec validation
            echo "Mode manuel - validation requise pour chaque nœud"
            
            # Obtention liste des nœuds
            local nodes=$(docker service ps "$service_name" --format "{{.Node}}" | sort -u)
            
            for node in $nodes; do
                echo "Validation nœud: $node"
                read -p "Continuer mise à jour sur $node? [y/N]: " -r
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    docker service update \
                        --constraint-add "node.hostname==$node" \
                        --force \
                        "$service_name"
                fi
            done
            ;;
    esac
    
    # Monitoring post-mise à jour
    monitor_service_health "$service_name"
}

monitor_service_health() {
    local service_name="$1"
    local timeout=300
    local elapsed=0
    
    echo "Monitoring santé service: $service_name"
    
    while [[ $elapsed -lt $timeout ]]; do
        local replicas_status=$(docker service ls --filter name="$service_name" --format "{{.Replicas}}")
        
        if [[ "$replicas_status" =~ ^([0-9]+)/\1$ ]]; then
            echo "Service stable: $replicas_status"
            break
        else
            echo "⏳ En attente stabilisation: $replicas_status"
            sleep 10
            elapsed=$((elapsed + 10))
        fi
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        echo "Timeout atteint - rollback automatique"
        docker service rollback "$service_name"
    fi
}
```

## Workflows Maintenance et Monitoring

### Monitoring Avancé

#### **Prometheus Integration**

```bash
=== PROMETHEUS EXPORTER ===
#!/bin/bash
# autopatch-prometheus-exporter.sh

generate_prometheus_metrics() {
    local metrics_file="/var/lib/node_exporter/textfile_collector/autopatch.prom"
    local timestamp=$(date +%s)
    
    {
        echo "# HELP autopatch_packages_total Total number of packages managed by autopatch"
        echo "# TYPE autopatch_packages_total gauge"
        echo "autopatch_packages_total $(dpkg -l | grep "^ii" | wc -l) $timestamp"
        
        echo "# HELP autopatch_backups_total Number of autopatch backups available"
        echo "# TYPE autopatch_backups_total gauge"
        echo "autopatch_backups_total $(find /var/tmp/autopatch_backups -name "backup_*" -type d | wc -l) $timestamp"
        
        echo "# HELP autopatch_last_update_timestamp Timestamp of last autopatch operation"
        echo "# TYPE autopatch_last_update_timestamp gauge"
        local last_update=$(stat -c %Y /var/log/autopatch/autopatch-manager.log 2>/dev/null || echo "0")
        echo "autopatch_last_update_timestamp $last_update"
        
        echo "# HELP autopatch_security_violations_total Number of security violations detected"
        echo "# TYPE autopatch_security_violations_total counter"
        local violations=$(grep -c "SÉCURITÉ COMPROMISE" /var/log/autopatch/*.log 2>/dev/null || echo "0")
        echo "autopatch_security_violations_total $violations $timestamp"
        
        echo "# HELP autopatch_disk_usage_bytes Disk usage by autopatch in bytes"
        echo "# TYPE autopatch_disk_usage_bytes gauge"
        local disk_usage=$(du -sb /var/tmp/autopatch* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        echo "autopatch_disk_usage_bytes $disk_usage $timestamp"
        
        echo "# HELP autopatch_daemon_status Status of autopatch daemon (1=active, 0=inactive)"
        echo "# TYPE autopatch_daemon_status gauge"
        local daemon_status=0
        if systemctl is-active autopatch-daemon.service >/dev/null 2>&1; then
            daemon_status=1
        fi
        echo "autopatch_daemon_status $daemon_status $timestamp"
        
    } > "$metrics_file.tmp"
    
    mv "$metrics_file.tmp" "$metrics_file"
}

# Crontab: */5 * * * * /usr/local/bin/autopatch-prometheus-exporter.sh

=== GRAFANA DASHBOARD JSON ===
{
  "dashboard": {
    "title": "AutoPatch Monitoring",
    "panels": [
      {
        "title": "Package Count Evolution",
        "type": "graph",
        "targets": [
          {
            "expr": "autopatch_packages_total",
            "legendFormat": "Total Packages"
          }
        ]
      },
      {
        "title": "Backup Status",
        "type": "singlestat",
        "targets": [
          {
            "expr": "autopatch_backups_total",
            "legendFormat": "Available Backups"
          }
        ]
      },
      {
        "title": "Security Violations",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(autopatch_security_violations_total[5m])",
            "legendFormat": "Violations per minute"
          }
        ]
      },
      {
        "title": "Last Update Age",
        "type": "singlestat",
        "targets": [
          {
            "expr": "time() - autopatch_last_update_timestamp",
            "legendFormat": "Seconds since last update"
          }
        ]
      }
    ]
  }
}
```

#### **Alerting Rules**

```bash
=== PROMETHEUS ALERTING RULES ===
# /etc/prometheus/rules/autopatch.yml

groups:
- name: autopatch.rules
  rules:
  
  - alert: AutoPatchSecurityViolation
    expr: increase(autopatch_security_violations_total[5m]) > 0
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "AutoPatch security violation detected"
      description: "{{ $value }} security violations detected in the last 5 minutes"
  
  - alert: AutoPatchDaemonDown
    expr: autopatch_daemon_status == 0
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "AutoPatch daemon is down"
      description: "AutoPatch daemon has been down for more than 5 minutes"
  
  - alert: AutoPatchNoRecentBackup
    expr: autopatch_backups_total == 0
    for: 1h
    labels:
      severity: warning
    annotations:
      summary: "No AutoPatch backups available"
      description: "No backups found - backup system may be failing"
  
  - alert: AutoPatchOldUpdate
    expr: (time() - autopatch_last_update_timestamp) > 604800  # 7 days
    for: 0m
    labels:
      severity: warning
    annotations:
      summary: "AutoPatch updates are outdated"
      description: "Last AutoPatch update was {{ $value | humanizeDuration }} ago"
  
  - alert: AutoPatchDiskUsageHigh
    expr: autopatch_disk_usage_bytes > 10737418240  # 10GB
    for: 30m
    labels:
      severity: warning
    annotations:
      summary: "AutoPatch disk usage is high"
      description: "AutoPatch is using {{ $value | humanizeBytes }} of disk space"

=== ALERTMANAGER CONFIGURATION ===
# /etc/alertmanager/alertmanager.yml

global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'autopatch@company.com'

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'autopatch-team'
  
  routes:
  - match:
      severity: critical
    receiver: 'autopatch-critical'
    repeat_interval: 1h

receivers:
- name: 'autopatch-team'
  email_configs:
  - to: 'autopatch-team@company.com'
    subject: '[AutoPatch] {{ .Status | toUpper }}: {{ .GroupLabels.alertname }}'
    body: |
      {{ range .Alerts }}
      Alert: {{ .Annotations.summary }}
      Description: {{ .Annotations.description }}
      Instance: {{ .Labels.instance }}
      {{ end }}

- name: 'autopatch-critical'
  email_configs:
  - to: 'autopatch-oncall@company.com'
    subject: '[CRITICAL] AutoPatch Security Alert'
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/XXX'
    channel: '#autopatch-alerts'
    text: 'CRITICAL: {{ .CommonAnnotations.summary }}'
```

### Maintenance Automatisée

#### **Scheduled Maintenance**

```bash
=== MAINTENANCE AUTOMATION ===
#!/bin/bash
# autopatch-maintenance.sh

scheduled_maintenance() {
    local maintenance_type="$1"  # daily, weekly, monthly
    local maintenance_window="$2"  # maintenance window duration in minutes
    
    echo "Maintenance AutoPatch programmée: $maintenance_type"
    echo "Fenêtre: $maintenance_window minutes"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + maintenance_window * 60))
    
    case "$maintenance_type" in
        daily)
            daily_maintenance_tasks
            ;;
        weekly)
            weekly_maintenance_tasks
            ;;
        monthly)
            monthly_maintenance_tasks
            ;;
    esac
    
    local current_time=$(date +%s)
    if [[ $current_time -gt $end_time ]]; then
        echo "ATTENTION: Maintenance a dépassé la fenêtre allouée"
        send_maintenance_overrun_alert
    fi
    
    echo "Maintenance $maintenance_type terminée"
}

daily_maintenance_tasks() {
    echo "Tâches maintenance quotidienne..."
    
    # Rotation logs
    logrotate -f /etc/logrotate.d/autopatch
    
    # Vérification espace disque
    check_disk_space
    
    # Validation intégrité sauvegardes récentes
    validate_recent_backups 3  # 3 derniers jours
    
    # Nettoyage fichiers temporaires
    cleanup_temp_files
    
    # Health check système
    /usr/local/bin/autopatch-manager.sh show-status --health-check
}

weekly_maintenance_tasks() {
    echo "Tâches maintenance hebdomadaire..."
    
    # Nettoyage sauvegardes anciennes
    /usr/local/bin/rollback.sh --cleanup-backups --days 30
    
    # Audit sécurité complet
    /usr/local/bin/rollback.sh --audit-report --comprehensive
    
    # Test de restauration
    test_backup_restoration
    
    # Optimisation base de données logs
    optimize_log_database
    
    # Mise à jour métriques hebdomadaires
    generate_weekly_metrics_report
}

monthly_maintenance_tasks() {
    echo "Tâches maintenance mensuelle..."
    
    # Archive logs anciens
    archive_old_logs
    
    # Nettoyage approfondi
    deep_system_cleanup
    
    # Test complet disaster recovery
    test_disaster_recovery_procedures
    
    # Révision configuration sécurité
    security_configuration_review
    
    # Génération rapport mensuel
    generate_monthly_report
}

=== CRONTAB MAINTENANCE ===
# Maintenance quotidienne à 2h00
0 2 * * * /usr/local/bin/autopatch-maintenance.sh daily 60 >> /var/log/autopatch/maintenance.log 2>&1

# Maintenance hebdomadaire dimanche à 3h00  
0 3 * * 0 /usr/local/bin/autopatch-maintenance.sh weekly 120 >> /var/log/autopatch/maintenance.log 2>&1

# Maintenance mensuelle le 1er à 4h00
0 4 1 * * /usr/local/bin/autopatch-maintenance.sh monthly 180 >> /var/log/autopatch/maintenance.log 2>&1

# Health check toutes les 5 minutes
*/5 * * * * /usr/local/bin/autopatch-manager.sh show-status --health-check --quiet || echo "$(date): Health check failed" >> /var/log/autopatch/health.log
```

## Templates et Scripts Utilitaires

### Templates d'Intégration

#### **Ansible Playbook**

```yaml
# autopatch-playbook.yml
---
- name: Deploy and Configure AutoPatch
  hosts: all
  become: yes
  vars:
    autopatch_version: "1.0"
    autopatch_home: "/usr/local/bin"
    backup_retention_days: 30
    monitoring_enabled: true
    
  tasks:
    - name: Create autopatch directories
      file:
        path: "{{ item }}"
        state: directory
        mode: '0755'
        owner: root
        group: root
      loop:
        - /var/log/autopatch
        - /var/tmp/autopatch
        - /var/tmp/autopatch_backups
        - /etc/autopatch
    
    - name: Download AutoPatch scripts
      get_url:
        url: "{{ autopatch_repo_url }}/{{ item }}"
        dest: "{{ autopatch_home }}/{{ item }}"
        mode: '0700'
        owner: root
        group: root
      loop:
        - autopatch-manager.sh
        - download.sh
        - install.sh
        - rollback.sh
    
    - name: Configure AutoPatch
      template:
        src: autopatch.conf.j2
        dest: /etc/autopatch/autopatch.conf
        mode: '0600'
        owner: root
        group: root
    
    - name: Install systemd service
      template:
        src: autopatch-daemon.service.j2
        dest: /etc/systemd/system/autopatch-daemon.service
      notify: reload systemd
    
    - name: Enable and start autopatch daemon
      systemd:
        name: autopatch-daemon
        enabled: yes
        state: started
        daemon_reload: yes
    
    - name: Configure log rotation
      template:
        src: autopatch-logrotate.j2
        dest: /etc/logrotate.d/autopatch
    
    - name: Schedule maintenance tasks
      cron:
        name: "{{ item.name }}"
        job: "{{ item.job }}"
        minute: "{{ item.minute }}"
        hour: "{{ item.hour }}"
        day: "{{ item.day | default('*') }}"
        weekday: "{{ item.weekday | default('*') }}"
        month: "{{ item.month | default('*') }}"
      loop:
        - name: "AutoPatch daily maintenance"
          job: "{{ autopatch_home }}/autopatch-maintenance.sh daily 60"
          minute: "0"
          hour: "2"
        - name: "AutoPatch weekly maintenance" 
          job: "{{ autopatch_home }}/autopatch-maintenance.sh weekly 120"
          minute: "0"
          hour: "3"
          weekday: "0"
    
  handlers:
    - name: reload systemd
      systemd:
        daemon_reload: yes
```

#### **Terraform Module**

```hcl
# modules/autopatch/main.tf

variable "instance_ids" {
  description = "List of EC2 instance IDs to configure with AutoPatch"
  type        = list(string)
}

variable "autopatch_version" {
  description = "AutoPatch version to deploy"
  type        = string
  default     = "1.0"
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "notification_topic_arn" {
  description = "SNS topic ARN for notifications"
  type        = string
}

# IAM role pour AutoPatch
resource "aws_iam_role" "autopatch_role" {
  name = "autopatch-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "autopatch_policy" {
  name = "autopatch-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream", 
          "logs:PutLogEvents",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "autopatch_policy_attachment" {
  policy_arn = aws_iam_policy.autopatch_policy.arn
  role       = aws_iam_role.autopatch_role.name
}

# Document SSM pour installation
resource "aws_ssm_document" "autopatch_install" {
  name          = "AutoPatch-Install"
  document_type = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Install and configure AutoPatch"
    parameters = {
      version = {
        type = "String"
        default = var.autopatch_version
        description = "AutoPatch version to install"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "installAutoPatch"
        inputs = {
          timeoutSeconds = "3600"
          runCommand = [
            "#!/bin/bash",
            "cd /tmp",
            "wget https://releases.autopatch.local/{{version}}/autopatch-bundle.tar.gz",
            "tar xzf autopatch-bundle.tar.gz",
            "cp autopatch-*.sh /usr/local/bin/",
            "chmod +x /usr/local/bin/autopatch-*.sh",
            "/usr/local/bin/autopatch-manager.sh manage-daemon --install --enable"
          ]
        }
      }
    ]
  })
}

# Association SSM pour installation
resource "aws_ssm_association" "autopatch_install" {
  count = length(var.instance_ids)
  
  name = aws_ssm_document.autopatch_install.name
  
  targets {
    key    = "InstanceIds"
    values = [var.instance_ids[count.index]]
  }
  
  parameters = {
    version = var.autopatch_version
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "autopatch" {
  dashboard_name = "AutoPatch-Monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AutoPatch/Operations", "TotalPackages"],
            [".", "BackupCount"],
            [".", "DiskUsagePercent"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "AutoPatch Metrics"
        }
      }
    ]
  })
}

output "autopatch_role_arn" {
  value = aws_iam_role.autopatch_role.arn
}

output "ssm_document_name" {
  value = aws_ssm_document.autopatch_install.name
}
```

---

**Auteur** : DECARNELLE Samuel  
**Version** : 1.0  
**Date** : 2025-07-22

> Ces workflows spécialisés fournissent des modèles d'intégration éprouvés pour déployer AutoPatch dans des environnements complexes et automatisés, garantissant une adoption réussie dans tous les contextes d'infrastructure moderne.
