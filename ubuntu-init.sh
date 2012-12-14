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
# upstart currently doesn't enable user jobs by default
#
UPSTART_CONF=$(cat <<EOF
<?xml version="1.0" encoding="UTF-8" ?>
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
EOF)
echo $UPSTART_CONF > /etc/dbus-1/system.d/Upstart.conf


#
# even when user jobs ARE enabled, upstart still can't 
# start them at boot so we will hack around this by
# manually looping over each user's .init folder jobs
# when networking is up
#
UPSTART_USER_JOBS=$(<<EOF
#
# user-jobs.conf
#

description "start user jobs when networking is up"

start on net-device-up

script
  cat /etc/passwd | while read LINE
  do
    USER=$(echo $LINE | cut -d: -f1)
    USER_HOME=$(echo $LINE | cut -d: -f6)
    if [ -d "$USER_HOME/.init" ]
    then
      ls $USER_HOME/.init | while read JOB
      do
        sudo -u $USER start ${JOB%.*}
      done
    fi
  done
end script
EOF)
echo $UPSTART_USER_JOBS > /etc/init/user-jobs.conf


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
mkdir .init
cd src


#
echo "--- installing nodejs ---"
NODE_VERSION="v0.8.16"
NODE_NAME="node-"$NODE_VERSION"-linux-x64"
wget http://nodejs.org/dist/"$NODE_VERSION"/"$NODE_NAME".tar.gz
tar -xvzf "$NODE_NAME".tar.gz
rm -rf "$NODE_NAME".tar.gz
for BIN in $( ls "$NODE_NAME"/bin ); do
  ln -s ../src/"$NODE_NAME"/bin/$BIN "$USER_HOME"/bin/$BIN;
done
NPM="$USER_HOME"/bin/npm


#
echo "--- installing coffee-script ---"
$NPM install coffee-script -g


#
echo "--- chowning the new user's files ---"
chown -R "$USER":"$USER" "$USER_HOME"


# grant node port binding capabilities below 1024 - must be done last as chown will remove this privilege
#echo "--- granting CAP_NET_BIND_SERVICE for Node ---"
#setcap 'cap_net_bind_service=+ep' "$USER_HOME"/src/"$NODE_NAME"/bin/node
