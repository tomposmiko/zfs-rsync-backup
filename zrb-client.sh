#!/bin/bash


apt install -y sudo rsync

name="backup-zrb"

useradd -m -U -s /bin/bash -d "/home/$name" "$name"
install -m 0700 -o "$name" -g "$name" -d "/home/$name/.ssh/"
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXQzHeVvpckvAXzsh/zeiahZtOljD96ii5nCFc9YX0u root@backup201" > "/home/$name/.ssh/authorized_keys"
chmod 0600 "/home/$name/.ssh/authorized_keys"
chown "$name:$name" "/home/$name/.ssh/authorized_keys"

echo -e "Cmnd_Alias C_ZRB = /usr/bin/rsync --server --sender -vlHogDtpre.iLsfxC --numeric-ids --inplace . //\nbackup-zrb	ALL=(ALL:ALL) NOPASSWD:C_ZRB" > /etc/sudoers.d/zrb
chmod 0440 /etc/sudoers.d/zrb

