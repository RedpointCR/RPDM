#!/bin/bash
# 12-01-2015 v1.0.0

CLUSTER_NAME=$1
CLUSTER_STORAGE_ACCOUNT=$2

CONTAINER=https://rpdm.blob.core.windows.net/installers
RPDM_VERSION=8.1.1.29784
RPDM_INSTALLER=RedPointDM-Server-$RPDM_VERSION-for-Ubuntu14.tgz
RPDM_WORKING_DIR=/mnt/rpdm
RPDM_INSTALLER_DIR=$RPDM_WORKING_DIR/RPDM_Server
RPDM_HOME=/opt/RedPointDM8
RPDM_CONF=/etc/redpointdm8.conf

RPDM_JARFILE=$RPDM_HOME/java/rpdmsdk-8.1.0-SNAPSHOT-shaded.jar
RPDM_SAMPLES=RedPointDM_Hadoop_Samples.tgz
RPDM_SAMPLES_URL=$CONTAINER/$RPDM_SAMPLES
RPDM_FIRSTRUN=/var/lock/rpdm-firstrun
RPDM_SHELL=$RPDM_HOME/program/rpdm_shell

if [ -e $RPDM_FIRSTRUN ]
then
    echo "This isn't a pristine VM; skip OS limits tuning. Delete $RPDM_FIRSTRUN if you want to make these modifications anyway."
else
	echo -n "Tuning OS..."
	touch $RPDM_FIRSTRUN
	# change limits -- assume machine is clean
	cat <<EOF >> /etc/security/limits.conf
*	soft	nofile	40000
*	hard	nofile	40000
EOF
	# change pam limits -- assume machine is clean
	ed /etc/pam.d/common-session <<EOF
$
i
session required pam_limits.so
.
w
q
EOF
	echo -n " done."
fi

if [ ! -d "$RPDM_WORKING_DIR" ]; then
	sudo mkdir -p $RPDM_WORKING_DIR
	sudo chmod 777 $RPDM_WORKING_DIR
fi
cd $RPDM_WORKING_DIR

if [ ! -e "$RPDM_INSTALLER" ]; then
	echo -n "Downloading $RPDM_INSTALLER from $CONTAINER..."
	sudo wget -o wget-rpdm.log $CONTAINER/$RPDM_INSTALLER
	echo " done."
fi

if [ ! -d "$RPDM_INSTALLER_DIR" ]; then
	echo -n "Unpacking $RPDM_INSTALLER to $RPDM_WORKING_DIR..."
	sudo tar xf $RPDM_INSTALLER
	echo " done."
	echo -n "Installing RPDM $RPDM_VERSION..."
	cd $RPDM_INSTALLER_DIR && sudo ./install.pl -y
	echo " done."
fi

#if [ -e "$RPDM_CONF" ] && ! grep -q JAVA_HOME "$RPDM_CONF"; then
#	echo "export JAVA_HOME=$JAVA_HOME" | sudo tee -a $RPDM_CONF
#fi

echo "Configuring RPDM temp spaces..."
echo "read /Settings/Site /tmp/site.xml" | $RPDM_SHELL
ed /tmp/site.xml <<EOF
/"settings"
/
a
      <m k="temp_spaces">
        <l k="temp_spaces">
          <m access="1" path="/mnt/tmp"/>
        </l>
      </m>
	  <m k="java" jvm_path="/usr/lib/jvm/java-8-openjdk-amd64/jre/lib/amd64/server/libjvm.so" use_classpath_env="0" use_jvm_path="1" />
.
w
q
EOF
echo "store /Settings/Site /tmp/site.xml" | $RPDM_SHELL
echo "Done configuring RPDM temp spaces."

exit 0