#!/bin/bash
#
# ubuntu-cloud-init.sh
#


#
USER="server"
ENVIRONMENT="production"


#
echo "--- redirecting output to /var/log/cloud-init-output.log ---"
exec &> /var/log/cloud-init-output.log 2>&1


#
echo "--- installing build tools & git ---"
apt-get update -y
apt-get install libcap2-bin -y
apt-get install build-essential -y
apt-get install git -y


#
echo "--- creating a non-privileged user ---"
groupadd "$USER"
useradd -g"$USER" -s/bin/bash -d/home/"$USER" -m "$USER"
USER_HOME=/home/"$USER"
cp -R /home/ubuntu/.ssh "$USER_HOME"/
echo 'PATH='$USER_HOME'/bin:$PATH' >> "$USER_HOME"/.tempbashrc
cat "$USER_HOME"/.bashrc >> "$USER_HOME"/.tempbashrc
mv "$USER_HOME"/.tempbashrc "$USER_HOME"/.bashrc


#
echo "--- configuring systemwide environment & shell ---"
PS1='\u@\h:\w\$(git branch 2> /dev/null | grep -e '\''\* '\'' | sed '\''s/^..\(.*\)/ {\1}/'\'')\$ '
echo 'export PS1='\"$PS1\" >> /etc/profile.d/"$USER".sh
echo 'export NODE_ENV='$ENVIRONMENT >> /etc/profile.d/"$USER".sh
echo "app soft nofile 40000" >> /etc/security/limits.conf
echo "app hard nofile 40000" >> /etc/security/limits.conf


#
# ideally these would go in a profile.d script, but the
# default .bashrc already has an alias entry for "l"
#
echo 'alias l="ls -alhBi --group-directories --color"' >> "$USER_HOME"/.bashrc
echo 'alias l="ls -alhBi --group-directories --color"' >> /home/ubuntu/.bashrc
echo 'alias l="ls -alhBi --group-directories --color"' >> /root/.bashrc


#
# remember to escape ` characters!
# to force a motd update run "sudo update-motd"
#
echo "--- addding link to motd banner ---"
chmod a+w /etc/update-motd.d/00-header
ln -s /etc/update-motd.d/00-header "$USER_HOME"/


#
echo "--- creating directories ---"
cd "$USER_HOME"
mkdir src
mkdir bin
mkdir lib
mkdir tmp


#
echo "--- installing nodejs ---"
NODE_VERSION="v0.8.15"
NODE_NAME="node-"$NODE_VERSION"-linux-x64"
wget http://nodejs.org/dist/"$NODE_VERSION"/"$NODE_NAME".tar.gz
tar -xvzf "$NODE_NAME".tar.gz
rm -rf "$NODE_NAME".tar.gz
mv "$NODE_NAME" src/
for BIN in $( ls src/"$NODE_NAME"/bin ); do 
  ln -s ../src/"$NODE_NAME"/bin/$BIN "$USER_HOME"/bin/$BIN;
done
NPM="$USER_HOME"/bin/npm


#
echo "--- installing coffee-script ---"
$NPM install coffee-script -g


#
echo "--- installing mon ---"
git clone https://github.com/visionmedia/mon.git
mv mon src/mon
cd src/mon
make
cd "$USER_HOME"
ln -s ../src/mon/mon bin/mon


#
echo "--- chowning new user's files ---"
chown -R "$USER":"$USER" "$USER_HOME"


# grant node port binding capabilities below 1024 - must be done last as chown will remove this privilege
echo "--- granting CAP_NET_BIND_SERVICE for Node ---"
setcap 'cap_net_bind_service=+ep' "$USER_HOME"/src/"$NODE_NAME"/bin/node
