#!/bin/bash
#
# ubuntu-cloud-init.sh
#


# default vars
[ -z $KEY ] && KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC46reWpJBzs+NpLTrpEP/wnBqSvp1tZIb9iotEwU210SBEXxC80R2SyH0dFcWmXyH6n+6QSy3yz246+cqu4lVuISAsCNfMiN87tmJzS6EAQuOOChes9Fv11a6tlIx8rUyuEdYx/hMkRC9/xfdpnTdCFbwPRJ9Z8i0xf8rV7Eg7zs5QQdniVZ7opxtppeEuX0wrtxC1haWmgBqIJ3uKWQQOJ+1TQH6xI0ds1osDV6y3VCYkAQHmxrWpiNQzHW0YOdty6IbOYb5mG5BEi0PtgrkAjH3IEnSM65571lgZRH/y1JQ/CTHDM03bMINce+AJNqx50xB6o7ycvl1pBKeyT3nL jessetane@Trusty-Steve-V.local"
[ -z $USER_NAME ] && USER_NAME="server"
[ -z $ENVIRONMENT ] && ENVIRONMENT="production"
[ -z $MOTD ] && MOTD='
       ___.                 __         
   __ _\  |__  __ __  _____/  |_ __ __ 
  |  |  \ __ \|  |  \/    \   __\  |  \
  |  |  / \_\ \  |  /   |  \  | |  |  /
  |____/|___  /____/|___|  /__| |____/ 
            \/           \/            

'


# redirect stdout to log
exec &> /var/log/cloud-init-output.log 2>&1
echo "--- ubuntu-init started ---"


#
echo "--- updating system ---"
apt-get update -y
apt-get upgrade -y


#
echo "--- creating a non-privileged user ---"
USER_HOME=/home/"$USER_NAME"
if [[ -z $(grep "^${USER_NAME}:" /etc/passwd) ]]
then
  groupadd "$USER_NAME"
  useradd -g"$USER_NAME" -s/bin/bash -d/home/"$USER_NAME" -m "$USER_NAME"
fi


# dirs
cd "$USER_HOME"
mkdir -p .ssh
mkdir -p bin
mkdir -p lib
mkdir -p src
mkdir -p tmp
mkdir -p init


# message-of-the-day
# remember to escape ` characters!
# force an update by running "sudo update-motd"
if [[ ! -e 00-header ]]
then
  chmod a+w /etc/update-motd.d/00-header
  ln -s /etc/update-motd.d/00-header ./
  FIRST=$(head -n 1 00-header)
  LAST=$(tail -n +2 00-header)
  echo -e "$FIRST\n\necho '$MOTD'\n\n$LAST" > 00-header
fi


# ssh
if [[ ! -e .ssh/authorized_keys || -z $(grep "$KEY" .ssh/authorized_keys) ]]
then
  chmod 700 .ssh
  echo -e "\n$KEY" >> .ssh/authorized_keys
  chmod 600 .ssh/authorized_keys
fi


# systemwide shell stuff
echo "--- configuring systemwide environment & shell ---"
PROFILE=/etc/profile.d/"$USER_NAME".sh
if [[ ! -e "$PROFILE" ]]
then
  PS1='\u@\h:\w\$(git branch 2> /dev/null | grep -e '\''\* '\'' | sed '\''s/^..\(.*\)/ {\1}/'\'')\$ '
  echo 'export PS1='\""$PS1"\" >> "$PROFILE"
  echo 'export NODE_ENV='"$ENVIRONMENT" >> "$PROFILE"
  echo 'alias l="ls -alhBi --group-directories --color"' >> "$PROFILE"
  
  # HACK: since ubuntu ships with an intense .bashrc 
  # that overwrites a lot of our global .profile, we re-source
  # the global from .profile, which runs after .bashrc
  cat /etc/passwd | while read LINE
  do
    HOME_DIR=$(echo "$LINE" | cut -d: -f6)
    [ -e "$HOME_DIR"/.profile ] && echo ". $PROFILE" >> "$HOME_DIR"/.profile
  done
fi


# default max open files is kinda low
LIMITS=/etc/security/limits.conf
if [[ -z $(grep "app soft nofile 40000" "$LIMITS") ]]
then
  echo "app soft nofile 40000" >> "$LIMITS"
  echo "app hard nofile 40000" >> "$LIMITS"
fi


# run $USER/init scripts on net-device-up
curl -o /etc/init/upstarter.conf https://raw.github.com/jessetane/upstarter/master/upstarter.conf


#
echo "--- installing packages ---"
apt-get install build-essential -y
apt-get install git -y


# install a node version manager and v0.9.6
curl -o bin/ninstall https://raw.github.com/jessetane/ninstall/master/ninstall && chmod +x bin/ninstall
sed -i "s/OS=.*/OS=\"linux\"/" bin/ninstall
sed -i "s|PREFIX=.*|PREFIX=$USER_HOME|" bin/ninstall
bin/ninstall v0.8.17
bin/ninstall v0.9.6
NPM=bin/npm


# chown everything in the new user's home folder and we're done
chown -R "$USER_NAME":"$USER_NAME" "$USER_HOME"


#
echo "--- all done! ---"