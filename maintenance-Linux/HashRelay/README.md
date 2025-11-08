# HashRelay

 `***Client–NAS handshake via hashes. “Proof > payload.”***`

The goal is to send automatically the backup that I created with this script to the NAS onto that been configured by the client. But that is too simple for me ! 

What I really want is to create an script onto the NAS that respond to a query send by the client to compare the backup file hash to see what backup need to be send to the NAS and what backup don't need to be send.

How this should work ? 
Inside the NAS, it should be a directory inside the home of the user that insitiated the script named backup.
The first time the user send a backup into the NAS nothing happen because it's the first and the NAS do not have something to compare. But since the NAS now have the backup, the next time the user lunch his scirpt onto his machine, the script should contact the NAS to ask for the of each file that exist onto that directory.

If the hash of the client and the hash of the NAS are different, that mean that the user have a newer version of the backup file.
So the backup should be deleted on the NAS (Not directly in case of a crash connection or else maybe 2 days after it could be moved inside a directory that delete the file in 2 days) and the user should automatically send the newer backup to the NAS.
