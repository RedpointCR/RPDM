#!/bin/bash
# 12-01-2015 v1.0.0

CLUSTER_NAME=$1
CLUSTER_STORAGE_ACCOUNT=$2

CONTAINER=http://dm-downloads.redpointglobal.com
RPDM_VERSION=8.0.3.29805
RPDM_INSTALLER=RedPointDM-Server-$RPDM_VERSION-for-Ubuntu14.tgz
RPDM_WORKING_DIR=/mnt/rpdm
RPDM_INSTALLER_DIR=$RPDM_WORKING_DIR/RPDM_Server
RPDM_HOME=/opt/RedPointDM8
RPDM_CONF=/etc/redpointdm8.conf

RPDM_JARFILE=$RPDM_HOME/java/rpdmsdk-8.0.1-SNAPSHOT-shaded.jar
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

hdfs dfs -test -e /rpdm/$RPDM_INSTALLER
if [ $? == 1 ]; then
	echo -n "Copying $RPDM_INSTALLER to HDFS..."
	hdfs dfs -mkdir /rpdm
	hdfs dfs -chmod a+rwx /rpdm
	hdfs dfs -copyFromLocal $RPDM_WORKING_DIR/$RPDM_INSTALLER /rpdm
	echo " done."
fi

CLUSTER_DIR=$RPDM_HOME/hadoop/clusters/hdi
if [ ! -d "$CLUSTER_DIR" ]; then
	echo -n "Retrieving cluster configuration..."
	sudo mkdir -p $CLUSTER_DIR
	sudo chmod 777 $CLUSTER_DIR
	hadoop jar $RPDM_JARFILE net.redpoint.hadoopconfigtool.Local -destinationDir $CLUSTER_DIR -appMasterJarPath $RPDM_JARFILE > configure.log 2>&1	
	echo " done."
fi

echo "Configuring RPDM for this cluster..."
cat > /tmp/hadoop.xml <<EOF
<dataitem version="2">
  <m checkin_note="" checkin_user="Administrator" datalever_version="$version" deleted="N" description="" group="Administrator" locked_by="" name="Hadoop" object_id="14" object_key="14" object_perms="223" path_id="7" subtype="HADOOP_SETTINGS" timestamp="1" type="SETTINGS" user="Administrator" vault_file_size="-1">
    <m k="settings" current_cluster="hdi" hdfs_mismatch_action="connect">
      <l k="clusters">
        <m hdfs_tempFolder="hdfs://mycluster/tmp" jvm_memory_mb="200" name="hdi" open_merge_file_limit="50" override_hadoop_user="0" project_trace_level="3" server_module_path="wasb://$CLUSTER_NAME@$CLUSTER_STORAGE_ACCOUNT.blob.core.windows.net/rpdm/$RPDM_INSTALLER" use_classpath_env="0" use_jvm_path="0" vendor="hortonworks">
          <m k="partition_task_defaults" enable_task_retry="0" task_headroom_mb="200" task_memory_mb="2048" task_retry_limit="1" tasks_per_worker="4"/>
          <m k="queue" override="0" queue="default"/>
          <m k="task_defaults" enable_task_retry="0" memory_aggressiveness="50" task_headroom_mb="200" task_memory_mb="2048" task_retry_limit="1" tasks_per_worker="4"/>
        </m>
      </l>
    </m>
  </m>
</dataitem>
EOF
echo "store /Settings/Hadoop /tmp/hadoop.xml" | $RPDM_SHELL
echo "Done configuring RPDM for this cluster."

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

cd $RPDM_WORKING_DIR
if [ ! -d samples ]; then
	echo -n "Downloading samples..."
	sudo wget $CONTAINER/$RPDM_SAMPLES
	echo " done."
fi
if [ ! -d $RPDM_SAMPLES ]; then
	echo -n "Extracting samples..."
	sudo tar xzf $RPDM_SAMPLES
	echo " done."
fi
hdfs dfs -test -d /rpdm/samples
if [ $? == 1 ]; then
	echo -n "Copying samples to HDFS..."
	hdfs dfs -copyFromLocal samples /rpdm
	hdfs dfs -chmod -R a+r /rpdm/samples
	echo " done."
fi

exit 0