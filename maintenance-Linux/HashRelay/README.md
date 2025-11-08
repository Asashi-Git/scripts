# HashRelay

 `***Client–NAS handshake via hashes. “Proof > payload.”***` 

Author: Decarnelle Samuel

This project aims to reduce network load within a LAN or WAN while guaranteeing the integrity of important backups across a network infrastructure. The tool is intended for small to large networks. It is usable only by your network administrators and, once in place, automates a major problem within complex network infrastructures: the availability of backups.

This software will include two agents: 
- A client agent.
- A server agent.

### HashRelay Client

#### Presentation

HashRelay-client is a service that manages the folders/files you want to back up. It uses a time-stamped backup naming scheme:

```bash
backup-$NAME-$NOW.tar.gz
```

- NAME is the name of the folder/file to back up.
- NOW is the timestamp (second–minute–hour–year–month–day) at which the backup was performed.

During the first installation, `hashrelay-client` must create a new service user (HashRelay-Client) with sudo rights, as well as a directory within the Linux operating system.
 
##### Distro-And-Pkgman-Detect
The service must automatically detect the Linux distribution it is running on to adjust the correct installation steps.  
Script path: `dependencies/distro-and-pkgman-detect/distro-and-pkgman-detect.sh`.

##### Pkg-Auto-Install
This works together with `pkg-auto-install.sh`, which installs the packages required for the agent based on the detected Linux distribution.  
It uses a file named `packages.list` that contains all necessary packages.

##### UFW-Configuration-Manager
This script sets UFW rules on the client so it can contact the HashRelay-server service on the correct port.  
Important: the server and the client must have the same open port. The script must ask which port the client and server will use to communicate.

##### SSH-Configuration-Manager
This script configures SSH so that the HashRelay-Client service user authenticates to the server using an RSA key only.

- On the server side, the script configures the SSH service and creates an RSA key for the client, stored in the `.ssh` directory of the HashRelay-server user.
- The script must also make the RSA key available to the client either via a temporary Python 3 server or via file transfer with `scp`.
- Ideally, the file is retrieved by the client via `scp` before finishing the SSH configuration on the server, so the link can be seamless.
- Since the access path will always be `/home/HashRelay-server/.ssh/HashRelay-client.key`, this can be automated.

##### Probe-viewer
This script checks, before or after each backup, whether the server is up by sending a request to the server.

- If the server responds, it is considered “Up.”
- If the server does not respond, it is considered “Down.”

This status is exposed to the main service so that when the user runs `sudo systemctl status HashRelay.client`, there is a section for the server (Up or Down).  
If the server is Down, the backup does not start, and a message is written to a log file indicating that the backup could not be performed because the server was considered down.

##### Contact IP
This script will be used by the client to obtain the server’s IP address and the port used to communicate ??? 



### HashRelay Server

#### Presentation




#### Utilisation

Afin d'ajouter un fichier au repertoire de backup, une foi le service demarer, le client n'aura qu'a faire la commande "`hashrelay -add FileName`" or "`hashrelay -a FileName`". 

Si un client ne veux plus faire de backup d'un dossier/fichier il n'aura qu'a effectuer la commande "`hashrelay -remove FileName`" or "`hashrelay -rm FileName`"

Une foi ces commande effectuer, le service doit automatiquement ajouter ce dossier/fichier au repertoire des backups.

Si le client veux connaitre les differentes possibilites il lui suffira de taper la commande "`hashrelay -h`" ou "`hashrelay --help`".

#### Installation
Pour installer HashRelay-Client sur votre machine il suffit de ...



### Old Version
The goal is to send automatically the backup that I created with this script to the NAS onto that been configured by the client. But that is too simple for me ! 

What I really want is to create an script onto the NAS that respond to a query send by the client to compare the backup file hash to see what backup need to be send to the NAS and what backup don't need to be send. 

How this should work ? 
Inside the NAS, it should be a directory inside the home of the user that insitiated the script named backup. 
The first time the user send a backup into the NAS nothing happen because it's the first and the NAS do not have something to compare. But since the NAS now have the backup, the next time the user lunch his scirpt onto his machine, the script should contact the NAS to ask for the of each file that exist onto that directory. 
If the hash of the client and the hash of the NAS are different, that mean that the user have a newer version of the backup file. 
So the backup should be deleted on the NAS (Not directly in case of a crash connection or else maybe 2 days after it could be moved inside a directory that delete the file in 2 days) and the user should automatically send the newer backup to the NAS.

