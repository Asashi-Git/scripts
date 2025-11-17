#!/usr/bin/env bash
# The pupose of this script is to look into the backup.conf file
# in the /usr/local/bin/HashRelay/backups-manager/backups.conf and
# fetch all the path of all the files the user have choosen to backup
# to get the hash of eatch file and place the hash into the hash.conf
# in /usr/local/bin/HashRelay/hash-printer/hash.conf
#
# This script must look if we have an actual cache of the backups inside the server
# to avoid contacting the server every time.
# if a new backup have a different hash then the cache, that mean the backup have
# been modified and must be backed up !
# else do nothing.
#
# Author: Decarnelle Samuel
