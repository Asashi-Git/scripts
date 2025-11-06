1. Service qui fait le reboot

sudo tee /etc/systemd/system/reboot-daily.service >/dev/null <<'EOF'
[Unit]
Description=Redémarrage quotidien

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl reboot
EOF

2. Timer à 02:00 tous les jours

sudo tee /etc/systemd/system/reboot-daily.timer >/dev/null <<'EOF'
[Unit]
Description=Daily reboot timer at 02:00am and 1pm

[Timer]
OnCalendar=*-*-* 02:00
OnCalendar=*-*-* 13:00
AccuracySec=1min
Unit=reboot-daily.service

[Install]
WantedBy=timers.target
EOF

3. Recharger systemd et activer le timer

sudo systemctl daemon-reload
sudo systemctl enable --now reboot-daily.timer

Vérifier la prochaine exécution

systemctl list-timers | grep reboot-daily
# et
systemctl status reboot-daily.timer
