# HashRelay

 `***Client–NAS handshake via hashes. “Proof > payload.”***` 

Author: Decarnelle Samuel

This project aims to reduce network load within a LAN or WAN while guaranteeing the integrity of important backups across a network infrastructure. The tool is intended for small to large networks. It is usable only by your network administrators and, once in place, automates a major problem within complex network infrastructures: the availability of backups.

This software will include two agents: 
- A client agent.
- A server agent.

### HashRelay Client

#### Presentation

HashRelay-client is a lightweight backup orchestrator for Linux that manages the folders/files you choose to protect and synchronizes them with a central server. It emphasizes bandwidth efficiency, verifiable integrity, and automated housekeeping.

- Backup naming: `backup-$NAME-$NOW.tar.gz`  
  - `NAME`: logical name of the file/folder being backed up  
  - `NOW`: timestamp in the order second–minute–hour–year–month–day

On first run, `hashrelay-client` creates a dedicated service user (HashRelay-Client) with the required privileges and prepares its working directories.

##### How it works (high level)
1. Backup Manager creates a time-stamped archive for each selected target.  
2. Hash Printer computes and records hashes in `hash-printer.list`.  
3. Probe-viewer checks server reachability (Up/Down) before/after each run.  
4. If a local backup is newer/different, Sender ships it to the server via `scp`.  
5. Receiver on the server accepts the backup and quarantines older generations.  
6. Delete Manager enforces retention (default: keep 2 newer iterations before deleting older ones).

##### Core setup components
- Distro-And-Pkgman-Detect  
  Detects the host distribution and package manager to tailor installation.  
  Path: `dependencies/distro-and-pkgman-detect/distro-and-pkgman-detect.sh`.

- Pkg-Auto-Install  
  Installs required packages using `pkg-auto-install.sh` and `packages.list`.

- UFW-Configuration-Manager  
  Configures client firewall rules so it can reach the server on a shared port (client and server must agree on the same port).

- SSH-Configuration-Manager  
  Enforces key-only auth for the HashRelay-Client user.  
  Generates/provisions the RSA key on the server and makes it available to the client (temporary Python server or `scp`).  
  Default path: `/home/HashRelay-server/.ssh/HashRelay-client.key`.

##### Synchronization and retention
- Contact IP: resolves the server IP and communication port for the client.  
- Sender/Receiver: transfers newer backups and relocates older ones server-side.  
- Delete Manager: deletes an older backup only after two newer generations exist (e.g., `backup-nginx.conf-021004-20251015.tar.gz` is removed once two newer backups are present).

##### Main controller
- HashRelay Client (controller) performs the initial configuration of all scripts, then exposes a CUI to:
  - show server status (Up/Down),
  - display total backup disk usage,
  - adjust settings such as backup interval and retention iterations.

#### Usage

Once the service is running:
- Add a file or directory to the backup set:  
  `hashrelay -add FileName` or `hashrelay -a FileName`
- Remove a file or directory from the backup set:  
  `hashrelay -remove FileName` or `hashrelay -rm FileName`
- The service updates the backup set automatically after each command.
- See available options:  
  `hashrelay -h` or `hashrelay --help`

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

---
#### More detailed scripts
##### Probe-viewer
This script checks, before each backup, whether the server is up by sending a request to the server.

- If the server responds, it is considered “Up.”
- If the server does not respond, it is considered “Down.”

This status is exposed to the main service so that when the user runs `sudo systemctl status HashRelay.client`, there is a section for the server (Up or Down).  
If the server is Down, the backup does not start, and a message is written to a log file indicating that the backup could not be performed because the server was considered down.

##### Contact IP
This script is used by the client to obtain the server’s IP address and the port used for communication.

##### Backup Manager
This script is used by `hashrelay-client` to back up the directory/file chosen by the user. It is the core of the HashRelay project.

##### Hash Printer
This script inspects the directory created by `backup-manager.sh` where backups are stored, then writes the hash of each backup file into `hash-printer.list`. This hash list is used to compare backups on the client and the server. If the hash differs, it means the client’s backup is newer or has been modified. In that case, `sender.sh` script should `scp -r` the new version to the server.

##### Sender
This script sends the backup considered newer to the server via `scp`.

##### Receiver
This script receives the newer backup on the server and moves any older backup with the same logical name (but different date and older hash) into a directory from which it will eventually be deleted.

##### Delete Manager
This script monitors the directory that stores older backups. By default, older backups are retained for 2 iterations. 

What does “2 iterations” mean? 
If there is a backup named `backup-nginx.conf-021004-20251015.tar.gz` (04h 10m 02s on 2025‑10‑15), it is deleted only after two newer backups exist in this directory. In other words, retention is based on how many newer generations are present, not strictly on the timestamp.

##### HashRelay Installer
This script is intended to be used only once. It asks the user whether to install the client service or the server service, then makes all dependencies executable. After that, it can launch either the `hashrelay-client` or `hashrelay-server` script to begin service configuration.

##### HashRelay Client
This script is the main controller of the service. It: 
- Performs the initial setup by correctly configuring all related scripts on first launch. 
- After setup, allows changing options such as the number of backup iterations to keep before deletion, and the interval between backups. 
- After initialization, running this script should display a console user interface (CUI) showing, for example: 
	- Whether the server is up or down, 
	- Total disk space used by backups, 
	- Options to adjust configuration.


#### Usage Example
Once the service has started, to add a file or directory to the backup set, run: 
- `hashrelay -add FileName` or `hashrelay -a FileName` 

If a client no longer wants to back up a file or directory, run: 
- `hashrelay -remove FileName` or `hashrelay -rm FileName`

After these commands are executed, the service automatically updates the backup set. 

To view all available options, run: 
- `hashrelay -h` or `hashrelay --help`

#### Installation
Make the installer executable and launch it with administrative privileges, then follow the guided configuration:

```bash
chmod +x hashrelay-installer.sh
sudo ./hashrelay-installer.sh
# Then choose the clients installer and follow the guided configuration
```
 
### HashRelay Server

#### Presentation



