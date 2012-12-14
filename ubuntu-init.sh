#!/bin/bash
#
# ubuntu-cloud-init.sh
#


#
# default vars
#
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


#
# redirect stdout to log
#
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


#
# prepend PATH to .bashrc
#
BIN_PATH='PATH='"$USER_HOME"'/bin:$PATH'
if [[ -z $(grep "^${BIN_PATH}$" "$USER_HOME"/.bashrc) ]]
then
  echo $BIN_PATH >> "$USER_HOME"/.tempbashrc
  cat "$USER_HOME"/.bashrc >> "$USER_HOME"/.tempbashrc
  mv "$USER_HOME"/.tempbashrc "$USER_HOME"/.bashrc
fi


#
# dirs
#
cd "$USER_HOME"
mkdir -p src
mkdir -p bin
mkdir -p lib
mkdir -p tmp
mkdir -p .ssh
mkdir -p .init


#
# message-of-the-day
# remember to escape ` characters!
# on RH, force an update by running "sudo update-motd"
#
if [[ ! -e 00-header ]]
then
  chmod a+w /etc/update-motd.d/00-header
  ln -s /etc/update-motd.d/00-header ./
  FIRST=$(head -n 1 00-header)
  LAST=$(tail -n +2 00-header)
  echo -e "$FIRST\n\necho '$MOTD'\n\n$LAST" > 00-header
fi


#
# ssh
#
if [[ ! -e .ssh/authorized_keys || -z $(grep "$KEY" .ssh/authorized_keys) ]]
then
  chmod 700 .ssh
  echo -e "\n$KEY" >> .ssh/authorized_keys
  chmod 600 .ssh/authorized_keys
fi


#
# systemwide shell stuff
#
echo "--- configuring systemwide environment & shell ---"
PROFILE=/etc/profile.d/"$USER_NAME".sh
if [[ ! -e "$PROFILE" ]]
then
  PS1='\u@\h:\w\$(git branch 2> /dev/null | grep -e '\''\* '\'' | sed '\''s/^..\(.*\)/ {\1}/'\'')\$ '
  echo 'export PS1='\""$PS1"\" >> "$PROFILE"
  echo 'export NODE_ENV='"$ENVIRONMENT" >> "$PROFILE"
  echo 'alias l="ls -alhBi --group-directories --color"' >> "$PROFILE"
fi


#
# the global "ls" alias will be masked by the one .bashrc already has
#
cat /etc/passwd | while read LINE
do
  USER_HOME=$(echo "$LINE" | cut -d: -f6)
  if [[ -e "$USER_HOME"/.bashrc ]]
  then
    sed -i 's/alias l=.*//g' "$USER_HOME"/.bashrc
  fi
done


#
# some db's want this
#
LIMITS=/etc/security/limits.conf
if [[ -z $(grep "app soft nofile 40000" "$LIMITS") ]]
then
  echo "app soft nofile 40000" >> "$LIMITS"
  echo "app hard nofile 40000" >> "$LIMITS"
fi


#
# upstart currently doesn't enable user jobs by default
#
UPSTART_CONF='<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE busconfig PUBLIC
  "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
  "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">

<busconfig>
  <!-- Only the root user can own the Upstart name -->
  <policy user="root">
    <allow own="com.ubuntu.Upstart" />
  </policy>

  <!-- Allow any user to invoke all of the methods on Upstart, its jobs
       or their instances, and to get and set properties - since Upstart
       isolates commands by user. -->
  <policy context="default">
    <allow send_destination="com.ubuntu.Upstart"
	   send_interface="org.freedesktop.DBus.Introspectable" />
    <allow send_destination="com.ubuntu.Upstart"
	   send_interface="org.freedesktop.DBus.Properties" />
    <allow send_destination="com.ubuntu.Upstart"
	   send_interface="com.ubuntu.Upstart0_6" />
    <allow send_destination="com.ubuntu.Upstart"
	   send_interface="com.ubuntu.Upstart0_6.Job" />
    <allow send_destination="com.ubuntu.Upstart"
	   send_interface="com.ubuntu.Upstart0_6.Instance" />
  </policy>
</busconfig>
'
echo "$UPSTART_CONF" > /etc/dbus-1/system.d/Upstart.conf


#
# even when user jobs ARE enabled, upstart still can't 
# start them at boot so we will hack around this by
# manually looping over each user's .init folder jobs
# when networking is up
#
UPSTART_USER_JOBS='#
# user-jobs.conf
#

description "start user jobs when networking is up"

start on net-device-up

script
  cat /etc/passwd | while read LINE
  do
    USER=$(echo "$LINE" | cut -d: -f1)
    USER_HOME=$(echo "$LINE" | cut -d: -f6)
    if [ -d "$USER_HOME/.init" ]
    then
      ls "$USER_HOME"/.init | while read JOB
      do
        sudo -u "$USER" start ${JOB%.*}
      done
    fi
  done
end script
'
echo "$UPSTART_USER_JOBS" > /etc/init/user-jobs.conf


#
echo "--- installing packages ---"
apt-get install build-essential -y
apt-get install git -y


#
# node
#
NODE_VERSION="v0.8.16"
NODE_NAME=node-"$NODE_VERSION"-linux-x64
if [[ ! -d src/"$NODE_VERSION" && ! -e bin/node ]]
then
  cd src
  wget http://nodejs.org/dist/"$NODE_VERSION"/"$NODE_NAME".tar.gz
  tar -xvzf "$NODE_NAME".tar.gz
  rm -rf "$NODE_NAME".tar.gz
  for BIN in $( ls "$NODE_NAME"/bin ); do
    ln -s ../src/"$NODE_NAME"/bin/$BIN "$USER_HOME"/bin/$BIN;
  done
  NPM="$USER_HOME"/bin/npm
fi


#
# chown everything in the new user's home folder and we're done
#
chown -R "$USER_NAME":"$USER_NAME" "$USER_HOME"


#
echo "--- all done! ---"