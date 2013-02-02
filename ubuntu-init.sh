#!/bin/bash
#
# ubuntu-cloud-init.sh
#


# defaults - you should change these or define them yourself before running this script
[ -z $KEY ] && KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC46reWpJBzs+NpLTrpEP/wnBqSvp1tZIb9iotEwU210SBEXxC80R2SyH0dFcWmXyH6n+6QSy3yz246+cqu4lVuISAsCNfMiN87tmJzS6EAQuOOChes9Fv11a6tlIx8rUyuEdYx/hMkRC9/xfdpnTdCFbwPRJ9Z8i0xf8rV7Eg7zs5QQdniVZ7opxtppeEuX0wrtxC1haWmgBqIJ3uKWQQOJ+1TQH6xI0ds1osDV6y3VCYkAQHmxrWpiNQzHW0YOdty6IbOYb5mG5BEi0PtgrkAjH3IEnSM65571lgZRH/y1JQ/CTHDM03bMINce+AJNqx50xB6o7ycvl1pBKeyT3nL jessetane@Trusty-Steve-V.local"
[ $USER == "root" ] && USER="server"
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
export HOME="/home/$USER"
if [[ -z $(grep "^${USER}:" /etc/passwd) ]]
then
  groupadd "$USER"
  useradd -g"$USER" -s/bin/bash -d/home/"$USER" -m "$USER"
fi


# dirs
cd "$HOME"
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


# shell setup
echo "--- .bashrc ---"
PS1='\u@\h:\w\$(git branch 2> /dev/null | grep -e '\''\* '\'' | sed '\''s/^..\(.*\)/ {\1}/'\'')\$ '

# for each user with a .bashrc file
cat /etc/passwd | while read LINE
do
  HOME_DIR=$(echo "$LINE" | cut -d: -f6)
  BASHRC="$HOME_DIR"/.bashrc
  if [[ -e "$BASHRC" && -z $(grep "NODE_ENV" "$BASHRC") ]]
  then
  
    # these should work even for non-interactive shells
    TEMP="$HOME_DIR"/temp
    echo '[ -d "$HOME/bin" ] && PATH="$HOME/bin:$PATH"' >> "$TEMP"
    echo "export NODE_ENV=$ENVIRONMENT" >> "$TEMP"
    echo 'function l { ls -alhBi --group-directories --color "$@"; }' >> "$TEMP"
    cat "$BASHRC" >> "$TEMP"
    cat "$TEMP" > "$BASHRC"
    rm "$TEMP"
    
    # interactive only
    echo "unalias l" >> "$BASHRC"
    echo "export PS1=\"$PS1\"" >> "$BASHRC"
  fi
done


# default max open files is kinda low
LIMITS=/etc/security/limits.conf
if [[ -z $(grep "app soft nofile 40000" "$LIMITS") ]]
then
  echo "app soft nofile 40000" >> "$LIMITS"
  echo "app hard nofile 40000" >> "$LIMITS"
fi


# point port 80 at 8080
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080


#
echo "--- installing system packages ---"
apt-get install build-essential -y
apt-get install git -y
apt-get install libncurses5-dev -y
apt-get install openssl -y
apt-get install libssl-dev -y
apt-get install libssl0.9.8 -y
apt-get install libc6-dev-i386 -y


# run $USER/init scripts on net-device-up
curl -o /etc/init/upstarter.conf https://raw.github.com/jessetane/upstarter/master/upstarter.conf


echo "--- installing user packages ---"


# install a node version manager and v0.8.18
if [ ! -e bin/ninstall ]
then
  curl -o bin/ninstall https://raw.github.com/jessetane/ninstall/master/ninstall
  chmod +x bin/ninstall
  sed -i "s/OS=.*/OS=\"linux\"/" bin/ninstall
  sed -i 's|PREFIX=.*|PREFIX="$HOME"|' bin/ninstall
  bin/ninstall v0.8.18
  bin/ninstall v0.9.8
  NPM=bin/npm
fi


# compile erlang from source
# if [ ! -d src/otp_src_R15B01 ]
# then
#   wget http://erlang.org/download/otp_src_R15B01.tar.gz
#   tar zxvf otp_src_R15B01.tar.gz
#   rm otp_src_R15B01.tar.gz
#   mv otp_src_R15B01 src/otp_src_R15B01
#   cd src/otp_src_R15B01
#   ./configure --prefix="$HOME"
#   make
#   make install
#   cd "$HOME"
# fi


# install an erlang version manager and R15B01
if [ ! -e bin/kerl ]
then
  curl -o bin/kerl https://raw.github.com/spawngrid/kerl/master/kerl
  sed -i 's|^KERL_BASE_DIR=.*|KERL_BASE_DIR="$HOME"/src/kerl|' bin/kerl
  chmod +x bin/kerl
  bin/kerl build R15B01 r15b01
  bin/kerl install r15b01 lib/erlang/r15b01
  echo '. "$HOME"/lib/erlang/r15b01/activate' | cat - .bashrc > temp
  cat temp > .bashrc && rm temp
fi


# install a process monitor
if [ ! -e bin/mon ]
then
  git clone https://github.com/visionmedia/mon.git
  mv mon src/mon
  cd src/mon
  make
  cd "$HOME"
  ln -s ../src/mon/mon bin/mon
fi


# chown everything in the new user's home folder and we're done
chown -R "$USER":"$USER" "$HOME"


#
echo "--- all done! ---"