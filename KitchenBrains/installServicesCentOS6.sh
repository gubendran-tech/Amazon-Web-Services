#!/bin/bash


#############
# Functions #
#############
usage () {

BASENAME=$(basename $0)
cat <<USAGE
Installation and update script.

usage: $BASENAME -ijkpqsy -a [ip address] -b [subnet mask] -c [default gateway] -D [dns server 1] -e [dns server 2] -g [interface] -o [s/d] -t [tagname] -m [ml sync ID] -w [ml sync server] -d [database name] -n [hostname] -x [xorg.conf] -z [possystem]
options:

   -p  		Installation or update connects to Production system
   -q		Installation or update connects to QA system
   -s		Installation or update connects to Staging system
   -i		Installation will be for an image
   -y		Answer all prompts with the default (non-interactive)
   -j		Installation or update is for Linux Input Device
   -k		Installation or update is for Linux Kitchen Advisor
   -a ip addr	Use this IP Address		
   -b subnet	Use this Subnet Mask
   -c gateway	Use this Default Gateway
   -D dns1	Use this primary DNS server	
   -e dns2	Use this secondary DNS server
   -g intr	Use this interface
   -o s/d	Use Static or Dynamic IP Scheme (enter either s or d)
   -t tagname	Tagname that is to be installed
   -m mlsyncID	Mobilink Sync ID for this installation to use
   -w mlserver  Mobilink server to sync this installation with
   -d dbname	Name that the database server will be accessible by
   -n hostname	Hostname for this installation to use
   -x xorg.conf	The filename of the xorg.conf to use or NO_Xorg_Configured to not configure Xorg
   -z possystem POS System for this installation to use or NO_POS_CONFIGURED to not configure POS System
   -R 		Script will only rsync the files from the build server and exit
It is used for first time installations and installing missing pieces.

USAGE
}

getArgs() {
while getopts "WvypqijkRsa:b:c:D:e:g:o:t:m:w:f:d:n:x:z:h?" opt
do
	case $opt in
		j)
			machinetype="InputDevice"
			;;
		k)
			machinetype="KitchenAdvisor"
			;;

		y)
			interactive=1
			;;
		p)
			buildtype="Production"
			;;
		s)
			buildtype="Staging"
			;;
		q)	
			buildtype="QA"
			;;
		v) 
			buildtype="Dev"
			;;
		i)	
			isimage="0"
			;;		
		a)
			if valid_ip "$OPTARG" ; then
				newip="$OPTARG"
			else
				failed 1 "Please enter a valid IP Address"
			fi
			;;
		b)
			if valid_ip "$OPTARG" ; then
				newnetmask="$OPTARG"
			else
				failed 1 "Please enter a valid Subnet Mask"
			fi
			;;
		c)
			if valid_ip "$OPTARG" ; then
				newdgateway="$OPTARG"
			else
				failed 1 "Please enter a valid Default Gateway"
			fi
			;;
		D)
			if valid_ip "$OPTARG" ; then
				newdns1="$OPTARG"
			else
				failed 1 "Please enter a valid Primary DNS Server"
			fi
			;;
		e)	
			if valid_ip "$OPTARG" ; then
				newdns2="$OPTARG"
			else
				failed 1 "Please enter a valid Secondary DNS Server"
			fi
			;;
		g)
			interface="$OPTARG"
			;;
		o)
			case "$OPTARG" in
				[sS]|[sS][tT][aA][tT][iI][cC])
					iptype="Static"; break ;;
				[dD]|[dD][yY][nN][aA][mM][iI][cC])
					iptype="Dynamic"; break ;;
				*)
					iptype="" ;;
			esac
			;;
		t)
			tagname="$OPTARG"
			;;
		m)
			mlsyncid="$OPTARG"		
			;;
		w)
			mlsyncserver="$OPTARG"
			;;
		d)
			sybasedbname="$OPTARG"
			;;
		n)
			usehostname="$OPTARG"
			;;
		x)
			xorgconfigused="$OPTARG"
			;;
		z)
			possystem="$OPTARG"
			;;
		W)
			configHostname
			exit 0
			;;
		R)
			echo "This process will only download the files needed for installation from the build server"
			preinstallCheck
			promptEnv
			setEnv
			promptMachineType
			updateSCK
			addUsers
			getSCKPackages
			failed 0 "Rsync necessary files only"
			exit 0
			;;
		h | ?)
			usage >&2
			exit 1
			;;
		\?)	
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		:)	
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
		*)
			usage >&2
			exit 1
			;;
	esac
done
}

preinstallCheck() {
# Check who is executing this script. Script must be run as root.
	echo "============================="
	[ "${EUID}" = "0" ]
	failed $?  "Checking if script is run as root user."
	failed 0 "SCK Installation started at $(date)"
	ifconfig | grep eth* >/dev/null 2>&1
	failed $? "ethernet configuration check"
	#ping $buildserver -c 1 -W 5 >/dev/null 2>&1
	echo $rsyncpw > $rsyncpwfile
	chmod 600 $rsyncpwfile
        rsync -aczh --dry-run --timeout=60 --password-file=$rsyncpwfile --stats --progress $buildcred@$buildserver::$prodloc/inStore/$(basename $buildverfile) $SCKHOME/temp/
	failed $? "Connection to deployment server check"
	# Checking CentOS version for compatibility
        installedosversion=$(cat /etc/redhat-release | awk '{print int($3)}')
        if [ $installedosversion = 6 ] ; then
                        echo "OS Version Check Passed! Continuing."
                else
                        echo "THIS IS THE WRONG INSTALLATION SCRIPT FOR THIS SYSTEM!"
                        echo "Delete this script from the KA and use the installServicesCentOS.sh script instead!"
                       	exit 1
                fi
	cd /root/
}

prepareProcess() {
	echo "============================="
	echo "= Starting install clean up ="
	echo "============================="
	[ -f /etc/init.d/sckmobilink ] && echo "Found sckmobilink service, making sure its stopped" && /etc/init.d/sckmobilink stop
	[ -f /etc/init.d/scktomcat ] && echo "Found scktomcat service, making sure its stopped" && /etc/init.d/scktomcat stop
	[ -f /etc/init.d/sckengine ] && echo "Found sckengine service, making sure its stopped" && /etc/init.d/sckengine stop
	[ -f /etc/init.d/sckserialproxy ] && echo "Found sckserialproxy service, making sure its stopped" && /etc/init.d/sckserialproxy stop
	[ -f /etc/init.d/scksybase ] && echo "Found scksybase service, making sure its stopped" && /etc/init.d/scksybase stop
	# QPM upgrades will fail if the new INSTOREDB variable isn't set right away
	sed -i "s/\(127.0.0.1.*\)/\1 $usehostname INSTOREDB/" /etc/hosts
	failed $? "setting INSTOREDB in hosts file"
}

updateOS() {
	promptYesNo "Would you like to check for OS level Updates?" "y"
	if [ "$YESNO" = "y" ] ; then
		yum clean all
		failed $? "yum clean"
		yum -y update
		failed $? "yum update"
		failed 0 "OS Updating"
	else
		failed 0 "Not Updating OS at this time"
	fi
}

checkIfImage() {
if [ -f $configimagefile ] ; then
	source $configimagefile
	promptEnv
        setEnv
	configSite
	chown -R sck:sck $SCKHOME/
	chown -R instore:instore /home/instore/
	sed -i 's/id:3\(.*initdefault.*\)/id:5\1/' /etc/inittab
	failed $? "set init 5"
	rm $configimagefile
	failed 0 "--- Congratulations! Site configuration complete at $(date)"
	exit 0
fi
}

promptEnv() {
	if [ -z $buildtype ] ; then
		echo "Please select the environment that this installation will be used in"
		sleep 1
		select name in $buildlist
		do
			buildtype="$name"
			if [ -n "$name" ] ; then
				break
			fi
		done
	fi
}

setEnv() {
	case $buildtype in
	
	QA)
		echo "This is using QA Environment for Installation"
		buildloc=$qaloc/inStore
		mlsyncserver="messaging.qa.mysck.net"
		;;
	Staging)
		echo "This is using Staging Environment for Installation"
		buildloc=$stagloc/inStore
		mlsyncserver="messaging.staging.mysck.net"
		;;

	Production)
	       	echo "This is using Production Environment for Installation"
	        buildloc=$prodloc/inStore
		mlsyncserver="messaging.mysck.net"
		;;
	Dev)
		echo -n "Please Enter Build Server Address: "
		read buildserver
		echo "Using Build Server: $buildserver"
		echo -n "Please enter the Rsync Path, /inStore will be added: "
		read buildloctemp
		buildloc=$buildloctemp/inStore
		echo "Using Rsync Path: " $buildloc
		echo -n "Please Enter mobilink server: "
		read mlsyncserver
		echo "Using mobilink server: $mlsyncserver"
		;;
	*)
		failed 1 "Invalid Build Type"
		;;
	esac
	echo "The build path to be used for this install is: $buildloc"
}

promptMachineType(){
	if [ -z "$machinetype" ] ; then
		machinetype=""
		echo "Please Select the machine type this installation is for:"
		sleep 1
		select name in $machinetypes
		do
			machinetype="$name"
			if [ -n "$name" ] ; then
				break
			fi
		done
	fi
	echo "This installation will be for a(n)" $machinetype"."
}

promptInputDeviceInfo(){
io=""
good=1
while [ $good != 0 ]
do
	echo -n "Enter IP Address of Kitchen Advisor this Input Device will be connecting to: "
	read io
	if valid_ip $io ; then
		good="0"
	else
		echo "Please enter a IP Address"
		good="1"
	fi
done
kaipaddress="$io"
unset io
}

promptImage() {
	if [ -z "$isimage" ] ; then
		isimage="1"
		promptYesNo "Will this installation be used to create a generic image" "n"
		if [ "$YESNO" = "y" ] ; then
			isimage="0"
		else
			isimage="1"
		fi
	fi
}
updateSCK() {
	if [ -f $SCKHOME/installedversion ] ; then
		echo "Detected previous installation of SCK Software."
		promptYesNo "Would you like to check for an updated version of SCK Software available" "y"
		if [ "$YESNO" = "y" ] ; then
			checkUpdate
			if [ "$?" = "0" ] ; then
				promptYesNo "Would you like to proceed with the update process" "y"
				if [ "$YESNO" = "y" ] ; then
					fullInstall=0
					update=1
				else
					echo "Exiting from upgrade process"
					exit 1
				fi
			else
				echo "Exiting from upgrade process"
				exit 1
			fi
	
		else
			promptYesNo "Would you like to proceed with installation anyway" "n"
			if [ "$YESNO" = "y" ] ; then
				promptYesNo "WARNING: This will erase all site specific configurations. Are you sure" "n"
					if [ "$YESNO" = "y" ] ; then
						failed 0 "Doing Full installation."
						fullInstall=1
						rm -rf $SCKHOME/*
						rm -rf /etc/init.d/sck*
						failed 0 "Removing SCKHOME directory contents"
					else
						echo "Exiting install process"
						exit 0;
					fi
			else
				echo "Exiting install process"
				exit 0;
			fi
		fi
	else
	failed 0 "Doing Full installation."
	fullInstall=1
fi
}

installOSPackages() {
	if [ ! -n "$(grep exclude /etc/yum.conf)" ] ; then
		echo "exclude = $excludepackages" >> /etc/yum.conf
		failed $? "masking excluded packages"
	else
		sed -i "s/\(exclude =\).*/\1 $excludepackages/" /etc/yum.conf
		failed $? "masking excluded packages"	
	fi
	addRepos
	yum install -y man rsync unzip zip sudo net-snmp libXtst wget libXt make vixie-cron which dos2unix bc bzip2 unzip acpid ntp compat-libstdc++-33 alsa-lib alsa-utils iptables
	failed $? "Standard utiliy installs"
	yum -y groupinstall "X Window System" "GNOME Desktop Environment" "Japanese Support" "Chinese Support" "Thai Support"
	failed $? "Install X Windows Gnome and language support packs"
	yum -y groupremove "Editors" "Mail Server" "Network Servers" "Text-based Internet"
	failed $? "yum groupremove"
	yum -y remove $excludepackages java
	yum -y install gdm gnome-panel firefox
	yum -y remove gnome-power-manager
	failed $? "remove firstboot rhgb Gnome Extras java"
	sleep 1
}

addRepos() {
	ARCH=$(uname -i)
	yum -y install yum-priorities
	failed 0 "Yum priorities install"
	cd /etc/yum.repos.d
	failed $? "cd to /etc/yum.repos.d"
	cp -p CentOS-Base.repo CentOS-Base.OLD
	failed $? "backing up CentOS-Base.repo"
	[ -f CentOS-Base.repo.rpmnew ] && mv CentOS-Base.repo.rpmnew CentOS-Base.repo
	failed 0 "copying CenOS-Base.repo.rpmnew is exists"
	[ -f rpmforge.* ] && rm rpmforge.*
	failed 0 "removing rpmforge repo"
	[ -f elrepo.* ] && rm elrepo.*
	failed 0 "removing elrepo repo"
	[ -f epel.* ] && rm epel.*
	failed 0 "removing epel repo"
	if [ -n "$(grep priority CentOS-Base.repo)" ] ; then
		echo priorities already set for CentOS-Base.repo
	else
		echo setting yum priorities for CentOS-Base.repo
		ex -s /etc/yum.repos.d/CentOS-Base.repo << EOF
:/\[base/ , /gpgkey/
:a
priority=1
.
:w
:/\[updates/ , /gpgkey/
:a
priority=1
.
:/\[addons/ , /gpgkey/
:a
priority=1
.
:/\[extras/ , /gpgkey/
:a
priority=1
.
:/\[centosplus/ , /gpgkey/
:a
priority=2
.
:/\[contrib/ , /gpgkey/
:a
priority=2
.
:w
:q
EOF
	fi
	failed 0 "adding priorities to CentOS-Base.repo"
}


disableServices() {
	[ -f /etc/init.d/atd ] && chkconfig --level 123456 atd off
	[ -f /etc/init.d/auditd ] && chkconfig --level 123456 auditd off
	[ -f /etc/init.d/cpuspeed ] && chkconfig --level 123456 cpuspeed off
	[ -f /etc/init.d/firstboot ] && chkconfig --level 123456 firstboot off
	[ -f /etc/init.d/kudzu ] && chkconfig --level 123456 kudzu off
	[ -f /etc/init.d/portmap ] && chkconfig --level 123456 portmap off
	[ -f /etc/init.d/netfs ] && chkconfig --level 123456 netfs off
	[ -f /etc/init.d/ip6tables ] && chkconfig --level 123456 ip6tables off
	[ -f /etc/init.d/pcscd ] && chkconfig --level 123456 pcscd off
	[ -f /etc/init.d/cups ] && chkconfig --level 123456 cups off
	[ -f /etc/init.d/mcstrans ] && chkconfig --level 123456 mcstrans off
	[ -f /etc/init.d/rhnsd ] && chkconfig --level 123456 rhnsd off
	[ -f /etc/init.d/yum-updatesd ] && chkconfig --level 123456 yum-updatesd off
	[ -f /etc/init.d/autofs ] && chkconfig --level 123456 autofs off
	[ -f /etc/init.d/avahi-daemon ] && chkconfig --level 123456 avahi-daemon off
	[ -f /etc/init.d/avahi-dnsconfd ] && chkconfig --level 123456 avahi-dnsconfd off
	[ -f /etc/init.d/nfslock ] && chkconfig --level 123456 nfslock off
}

changeOSSettings() {
	echo "RUN_FIRSTBOOT=no" > /etc/sysconfig/firstboot
	sed -i 's/id:3\(.*initdefault.*\)/id:5\1/' /etc/inittab
	failed $? "set init 5"
	# Enabling TRIM for SSD
	tune2fs -o discard /dev/sda1 
	if [ -z "$(grep "SCK Customized" /etc/profile)" ] ; then
		{
		echo '# START SCK Customized Section '
		echo 'NORMAL="\[\e[0m\]" '
		echo 'RED="\[\e[1;31m\]" '
		echo 'GREEN="\[\e[1;32m\]" '
		echo 'if [[ $EUID == 0 ]] ; then '
		echo '        PS1="$RED\u@\h [$NORMAL\W$RED]# $NORMAL" '
		echo 'else '
		echo '        PS1="$GREEN\u@\h [$NORMAL\W$GREEN]\$ $NORMAL" '
		echo 'fi '
		echo 'export HISTCONTROL=erasedups'
		echo 'export HISTSIZE=1000'
		echo 'export HISTFILESIZE=1000'
		echo "alias ifconfig='sudo ifconfig'"
		echo "alias ll='ls -l'"
		echo "EDITOR=vi"
		echo "export EDITOR"
		echo "export LOGS=$SCKHOME/logs"
		echo "export TLOGS=/home/sck/tomcat/logs"
		echo '# END SCK Customized Section'
		}  >> /etc/profile
		failed $? "set up profile"
	else
		failed 0 "profile already set"
	fi
	if [ -z "$(getenforce | grep "Disabled")" ] ; then
		setenforce 0
		failed $? "set SELinux to premissive"
		sed -i 's/\(SELINUX=\).*/\1disabled/' /etc/selinux/config
		failed $? "disable SELinux premanently"
	else
		failed 0 "SELinux Disabled"
	fi
	if [ -f "/etc/sudoers.tmp" ]; then
	    exit 1
	fi
	touch /etc/sudoers.tmp
	sed 's/.*\(%wheel.*NOPASSWD:\)/\1/g' /etc/sudoers > /etc/sudoers.new
	sed -i 's/\(^Defaults.*requiretty\)/#\1/g' /etc/sudoers.new
	visudo -q -c -f /etc/sudoers.new
	if [ $? -eq "0" ]; then
	    cp /etc/sudoers.new /etc/sudoers
    	fi
	rm /etc/sudoers.tmp
	#yum -y install pciutils
	#videocard=$(lspci | grep "VGA")
	#if echo $videocard | grep -i "nvidia" > /dev/null ; then
	#	failed 0 "Detected Intel based Video Card."
	# I'm blacklisting the Intel audio that doesn't work with QPM M6895	
	echo "install snd-hda-intel /bin/true" > /etc/modprobe.d/sound
	#	failed $? "Blacklisting Nvidia Sound Card"
	#fi
	alsaunmute 0
	#failed 0 "alsaunmute"
}

addUsers() {
	echo ==================================
	echo = Starting install user creation =
	echo ==================================
	if useradd -G wheel -s/bin/bash -m sck > /dev/null; then
		echo "Creating password for SCK user"
		echo Sck2Support  | passwd sck  --stdin > /dev/null
	fi
	if useradd -s/bin/bash -m instore > /dev/null; then
		echo "Creating password for Instore user"
		echo Instore1User  | passwd instore  --stdin > /dev/null
	fi
	if grep sck /etc/passwd && grep instore /etc/passwd > /dev/null ; then
		echo users created successfully
	else
		echo user creation failed
		exit 1
	fi
	usermod -aG wheel,uucp,dialout,lock sck
	failed $? "add sck to wheel,uucp,lock groups"
	echo =============================
	echo = End install user creation =
	echo =============================
}

getSCKPackages() {
	mkdir -p $SCKHOME/temp
	failed $? "Create $SCKHOME/temp"
	cd $SCKHOME/temp
	failed $? "Go to $SCKHOME/temp"
	if [ "$machinetype" == "KitchenAdvisor" ] ; then
		getfiles "$stagingloc/apache-tomcat*.tar.gz" "$SCKHOME/temp/" "rsync tomcat"
		getfiles "$stagingloc/apcupsd*.rpm" "$SCKHOME/temp/" "rsync apcups daemon"	
		getfiles "$stagingloc/fonts.zip" "$SCKHOME/temp/" "rsync Windows Fonts"
		getfiles "$stagingloc/java7/jdk*" "$SCKHOME/temp/" "rsync java"
		getfiles "$stagingloc/java7/rxtx*" "$SCKHOME/temp/" "rsync rxtx"
		getfiles "$stagingloc/sybase-oem-11-*.tar.gz" "$SCKHOME/temp/" "rsync sybase"
		getfiles "$stagingloc/x11vnc*" "$SCKHOME/temp/" "rsync x11vnc"
		getfiles "$stagingloc/apf*" "$SCKHOME/temp/" "rsync apf"
		getfiles "$stagingloc/unclutter*x86_64.rpm" "$SCKHOME/temp/" "rsync unclutter"
		getfiles "$stagingloc/nvidia*.rpm" "$SCKHOME/temp/" "rsync nvidia-x11"
		getfiles "$stagingloc/nvidia*.rpm" "$SCKHOME/temp/" "rsync kmod-nvidia"
		getfiles "$buildloc/*" "$SCKHOME/temp/" "rsync sck build files"
	fi
	if [ "$machinetype" == "InputDevice" ] ; then
		getfiles "$stagingloc/fonts.zip" "$SCKHOME/temp/" "rsync Windows Fonts"
		getfiles "$stagingloc/jdk*" "$SCKHOME/temp/" "rsync java"
		getfiles "$stagingloc/inputdevicedrivers.tgz" "$SCKHOME/temp/" "rsync input device drivers"
		getfiles "$stagingloc/apf*" "$SCKHOME/temp/" "rsync apf"
		getfiles "$stagingloc/unclutter*x86_64.rpm" "$SCKHOME/temp/" "rsync unclutter"
		getfiles "$buildloc/BlackBox*.zip" "$SCKHOME/temp/" "rsync BlackBox.zip"
		getfiles "$buildloc/buildVersion.txt" "$SCKHOME/temp/" "rsync tag file"
	fi
	failed $? "rsync install files"
}

installSCKPackages() {
	[ "$machinetype" != "InputDevice" ] && installSybaseTar
	installSCKEngine
	move3rdPackages
	installJava
	[ "$machinetype" != "InputDevice" ] && installTomcat
	[ "$machinetype" != "InputDevice" ] && installAPC
	setupNTP
}

installSybaseTar() {
	[ -d /opt/sybase ] && rm -rf /opt/sybase
	failed 0 "removing /opt/sybase directory if it exists"
	tar --overwrite -pPxf $SCKHOME/temp/sybase-oem-11*.tar.gz -C /
	yum -y install glibc.i686
	failed $? "Installed Sybase and Latest EBF"
}

installSCKEngine() {
	[ -d $SCKHOME/sckengine ] && rm -rf $SCKHOME/sckengine && failed $? "Removing sckengine directory"
	cd $SCKHOME/temp
	failed $? "Go to $SCKHOME/temp"
	cp BlackBox_KFC_UK.zip $SCKHOME
	failed $? "Copy BlackBox.zip to home"
	cd $SCKHOME
	failed $? "Go to sck home"
	unzip -oq BlackBox_KFC_UK.zip
	failed $? "unzip BlackBox.zip"
	[ "$machinetype" == "InputDevice" ] && rm -rf $SCKHOME/sckengine
}

move3rdPackages() {
	cd $SCKHOME/temp
	failed $? "Go to $SCKHOME/temp"
	cp jdk-* $SCKHOME/install/
	cp rxtx-2.2-0.6.20100211.el6.x86_64.rpm $SCKHOME/install/
	failed $? "copy java"
	cp fonts.zip $SCKHOME/install/
	failed $? "copy windows fonts for java"
	cp apf* $SCKHOME/install/
	failed $? "copy apf rpm"
	cp unclutter* $SCKHOME/install/
	failed $? "copy unclutter rpm"
	if [ "$machinetype" != "InputDevice" ] ; then
		cp $tomcatarc $SCKHOME/install/
		failed $? "copy tomcat"
		cp apcupsd-*.rpm $SCKHOME/install/
		failed $? "copy apc ups"
		cp engine.war $SCKHOME/sckengine/deploy/
		cp instore.war $SCKHOME/install/instore.war
		cp -f kfcinstore.war $SCKHOME/install/kfcinstore.war
		failed $? "copy war"
		cp *.sql $SCKHOME/install/
		failed $? "copy sql"
		cp x11vnc-*.rpm $SCKHOME/install/
		failed $? "copy x11vnc"
	fi
}
installJava() {
	if [ ! -d /usr/java/jdk1.7.0_2 ] ; then
		rpm -e jdk
		rpm -ivh $SCKHOME/install/jdk-7u2-linux-x64.rpm
		failed $? "Install Sun Java"
	else
		failed 0 "java already installed"
	fi
	find /usr/java/latest/jre/lib/fonts -maxdepth 1 -type f -not -name "*Lucida*" -delete
	failed 0 "Remove fonts from old directory in Java is exist"
	unzip -oq $SCKHOME/install/fonts.zip -d /usr/share/fonts/
	failed $? "Unzip Microsoft Fonts"
	cp $SCKHOME/install/ProductionMonitorLogging.properties /usr/java/latest/jre/lib/logging.properties
	failed $? "Copy ProductionMonitor Java Logging"
	cp $SCKHOME/install/fastlogging.jar /usr/java/latest/jre/lib/ext/fastlogging.jar
	failed $? "copy java logging jar"
	if [ "$machinetype" != "InputDevice" ] ; then
		# I'm installing the new RXTX libraries for Java 1.7 here
		yum -y install jpackage-utils
		rpm -ivh --nodeps $SCKHOME/install/rxtx-2.2-0.6.20100211.el6.x86_64.rpm
		cp /usr/share/java/RXTXcomm.jar /usr/java/latest/jre/lib/ext
		failed $? "copy rxtx jar to java"
	fi
}
installTomcat() {
	if [ -d /usr/local/apache-tomcat* ] ; then
		rm -rf /usr/local/apache-tomcat*
		failed $? "Removing previous Apache Tomcat Directory"
		rm -rf $SCKHOME/tomcat
		failed $? "Removing symlink to previous Apache Tomcat Directory"
	else
		failed 0 "No previous versions of Apache Tomcat Found"
	fi
	tar -C /usr/local -xf $SCKHOME/install/apache-tomcat-6.0.18.tar.gz
	failed $? "untar tomcat"
	ln -s /usr/local/apache-tomcat-6.0.18 $SCKHOME/tomcat
	failed $? "create symlink for tomcat"
	mv $SCKHOME/tomcat/conf/server.xml $SCKHOME/tomcat/conf/server.xml.orig
	failed $? "backup tomcat conf"
	cp $SCKHOME/install/server.6.xml $SCKHOME/tomcat/conf/server.xml
	failed $? "copy new tomcat conf"
	cp $SCKHOME/install/*.war $SCKHOME/tomcat/webapps
	failed $? "copy war to tomcat deploy"
	unzip -oq $SCKHOME/tomcat/webapps/instore.war -d $SCKHOME/tomcat/webapps/instore
	unzip -oq $SCKHOME/tomcat/webapps/kfcinstore.war -d $SCKHOME/tomcat/webapps/kfcinstore
	failed $? "unzip war"
	rm $SCKHOME/tomcat/webapps/ROOT/index*
	failed $? "Removing Tomcat Admin pages"
	{
		echo "<html>"
		echo ""
		echo "<head>"
		echo "<meta http-equiv=\"refresh\" content=\"0;URL=/instore/\">"
		echo "</head>"
		echo "<body>"
		echo "</body>"
		echo ""
		echo "</html>"
	} > $SCKHOME/tomcat/webapps/ROOT/index.html
	# Modifying the context.xml for Mantis 5278
	sed -i 's/<Context>/<Context crossContext=\"true\">'/ $SCKHOME/tomcat/conf/context.xml
}
	



installAPC() {
	cd $SCKHOME/install
	failed $? "go to install dir"
	yum -y install mailx
	rpm --nosignature --force -ivh apcupsd-*.rpm
	failed $? "install apc ups"
}
setupNTP() {
	if [ -f /etc/init.d/ntpd ] ; then
   		failed 0 "NTP installed"
		/etc/init.d/ntpd stop
		failed $? "Stopping ntpd service"
	fi
	chkconfig --add ntpd
	failed $? "Adding ntp to startup"
	chkconfig ntpd --levels 2345 on
	failed $? "Adding ntp to runlevels"
	cp $SCKHOME/install/ntp.conf /etc/ntp.conf
	failed $? "Copying modified ntp.conf"
	chmod 700 /etc/ntp.conf
	failed $? "chmod ntp.conf"
	cp $SCKHOME/install/step-tickers /etc/ntp/step-tickers
	failed $? "Copying modified step-tickers"
	chmod 700 /etc/ntp/step-tickers
	failed $? "chmod step-tickers"
	touch /var/log/ntp.log
	failed $? "touch ntp log"
	chmod 644 /var/log/ntp.log
	failed $? "correct permissions on ntp log"
	ntpdate mail.mysck.net
	failed 0 "Updating the time first"
	/etc/init.d/ntpd start
	failed $? "Starting ntpd service"
}

installFreshDB() {
	mkdir -p $SCKHOME/db/
	failed $? "make db dir"
	rm -rf $SCKHOME/db/*
	failed $? "clear db dir"
	cp $SCKHOME/temp/*.db $SCKHOME/db/
	failed $? "copy database file"
	cp $SCKHOME/temp/*.log $SCKHOME/db/
	failed $? "copy database log"
	chown -R sck:sck $SCKHOME/db/
	failed $? "chown database to sck"
}
installSCKInitScripts() {
	cd $SCKHOME/install
	failed $? "go to install dir"
	setInit sckengine
	failed $? "Install sckengine init.d script"
	setInit sckserialproxy
	failed $? "Install sckengine init.d script"
	setInit scksybase
	failed $? "Install scksybase init.d script"
	setInit scktomcat
	failed $? "Install scktomcat init.d script"
	setInit sckrestart -n
	failed $? "Install sckrestart init.d script"
	setInit sckmobilink
	failed $? "Install sckmobilink init.d script"
}
installSCKAdminScripts() {
	cp $SCKHOME/install/mobilink/cert.pem $SCKHOME/db
	failed $? "copy cert for mobilink"
	cp $SCKHOME/install/sck.rules /etc/udev/rules.d
	failed $? "copy udev rules"
	find / -name runForecast*.sh -delete
	failed 0 "remove forecast engine script"
	cp $SCKHOME/install/mobilinkonetime.sh $SCKHOME/admin/
	failed $? "Copy mobilinkonetime.sh to SCKHOME/admin/"
	chmod a+x $SCKHOME/admin/*.sh
	chmod a+x $SCKHOME/install/*.sh
	failed $? "chmod SCKHOME/*.sh"
	chmod 755 $SCKHOME/admin
	failed $? "chmod forecast engine script in SCKHOME/admin/"
	find / -name clean_tomcat_logs.sh -delete
	failed 0 "removing cleantomcatlogs script"	
	find / -name runforecast* -delete
	failed 0 "remove forecast engine log rotate"
	cp $SCKHOME/install/tomcatlr /etc/logrotate.d/tomcat
	failed $? "copy tomcat log rotate"
	cp $SCKHOME/install/sybaselr /etc/logrotate.d/sybase
	failed $? "copy sybase database and mobilink log rotate"
	cp $SCKHOME/install/serialproxylr /etc/logrotate.d/serialproxy
	failed $? "copy serialproxy log rotate"
	cp $SCKHOME/install/movesckrestart /etc/cron.d/movesckrestart
	failed $? "move cron job that copies sckrestart cron job"
	chmod 600 /etc/cron.d/movesckrestart 
	failed $? "chmod movesckrestart cron job"
}

configInstoreDesktop() {
		[ -f /etc/gdm/custom.conf ] && \
		cp /etc/gdm/custom.conf /etc/gdm/custom.conf.orig && \
		cp -f $SCKHOME/install/custom.conf /etc/gdm/custom.conf
		failed $? "backup gdm custom.conf"
		mkdir -p /home/instore/.config/autostart/
	{
	echo '[Desktop Entry]'
	echo 'Encoding=UTF-8'
	echo 'Version=1.0'
	echo 'Type=Application'
	echo 'Name=JavaWS'
	echo 'Comment='
	echo 'Exec=javaws -Xnosplash "http://localhost:8080/instore/launchQPM.admin"'
	echo 'StartupNotify=false'
	echo 'Terminal=false'
	echo 'Hidden=false'
	} > /home/instore/.config/autostart/javaws.desktop
    {
	echo 'grant {'
	echo 'permission java.security.AllPermission;'
	echo 'permission java.awt.AWTPermission "showWindowWithoutWarningBanner";'
    echo 'permission java.security.AllPermission;'
    echo '};'
	} > /usr/java/latest/jre/lib/security/java.policy
	failed $? "Writing JavaWS autostart file modifications"
	# I'm creating the deployment.properties files here
	{
	echo 'deployment.cache.enabled=false'
	echo 'deployment.user.security.exception.sites=/home/instore/.java/deployment/exception.sites'
	} > /home/instore/.java/deployment/deployment.properties
	{
	echo 'localhost'
	} > /home/instore/.java/deployment/exception.sites
	yum -y install vino
	su - instore -c "
	gconftool-2 -s -t bool /desktop/gnome/remote_access/enabled true
	gconftool-2 -s -t string /desktop/gnome/remote_access/vnc_password c2NrX3N1cHBvcnQK
	gconftool-2 -s -t list --list-type string /desktop/gnome/remote_access/authentication_methods '[vnc]'
	gconftool-2 --type bool --set /desktop/gnome/remote_access/prompt_enabled 0
	"
	# I'm disabling autoplay here to fix Mantis 6110
	gconftool-2 --direct --config-source xml:readwrite:/etc/gconf/gconf.xml.mandatory --type bool --set /desktop/gnome/volume_manager/automount_media false
    gconftool-2 --direct --config-source xml:readwrite:/etc/gconf/gconf.xml.mandatory --type bool --set /desktop/gnome/volume_manager/automount_drives false
    gconftool-2 --direct --config-source xml:readwrite:/etc/gconf/gconf.xml.mandatory --type bool --set /desktop/gnome/volume_manager/autophoto false
	tar -C /home/instore -xf $SCKHOME/install/instoregconf.tar.gz
	failed $? "Enabling VNC for instore user"
	cp $SCKHOME/install/custom.conf /etc/gdm/custom.conf
	failed $? "copy new gdm custom.conf"
	installUnclutter
}

installUnclutter() {
	rpm --nosignature --force -Uvh $SCKHOME/install/unclutter*
	failed 0 "installing unclutter"
	mkdir -p /home/instore/.config/autostart/
	failed $? "mkdir config/autostart/ for instore user"
	[ -f /home/instore/.config/autostart/unclutter.desktop ] && rm /home/instore/.config/autostart/unclutter.desktop
	failed 0 "removing previous unclutter.desktop file if exist"
	{
	echo '[Desktop Entry]'
	echo 'Version=1.0'
	echo 'Type=Application'
	echo 'Encoding=UTF-8'	
	echo 'Name=Unclutter'
	echo 'GenericName=GUI Tweak'
	echo 'Comment=This application will hide the mouse cursor when idle'
	echo 'TryExec=unclutter'
	echo 'Exec=unclutter -root'
	echo 'Terminal=false'
	echo 'StartupNotify=false'
	echo 'Hidden=false'
	} > /home/instore/.config/autostart/unclutter.desktop
	failed $? "Writing unclutter autostart file"
	mkdir -p $SCKHOME/.config/autostart/
	failed $? "mkdir config/autostart/ for sck user"
	if [ "$machinetype" != "InputDevice" ] ; then
	{
	echo '[Desktop Entry]'
	echo 'Version=1.0'
	echo 'Type=Application'
	echo 'Encoding=UTF-8'	
	echo 'Name=Gnome Terminal'
	echo 'GenericName=Terminal'
	echo 'Comment=This application will launch the gnome-terminal application'
	echo 'TryExec=gnome-terminal'
	echo 'Exec=gnome-terminal'
	echo 'Terminal=false'
	echo 'StartupNotify=false'
	echo 'Hidden=false'
	} > $SCKHOME/.config/autostart/gnome-terminal.desktop
	failed $? "Writing gnome=terminal autostart file"
	fi
}

createDirsFixPermissions() {
	mkdir -p $SCKHOME/logs
	failed $? "Make sck logs dir"
	chmod 777 $SCKHOME/logs
	failed $? "chmod sck logs dir"
	mkdir -p $SCKHOME/backup
	failed $? "make sck backup dir"
	[ -d $SCKHOME/restore ] && \
		rm -rf $SCKHOME/restore && \
		failed $? "Removing sck restore directory"
	[ -d $SCKHOME/updates ] && \
		rm -rf $SCKHOME/updates && \
		failed $? "removing sck updates dir"
	[ -d $SCKHOME/saved_updates ] && \
		rm -rf $SCKHOME/saved_updates && \
		failed $? "removing sck saved_updates dir"	
	mkdir -p /home/instore/logs
	failed $? "make instore logs dir"
	touch /home/instore/logs/ProductMonitor_0.log
	failed $? "touch ProductMonitor Log"
	chmod 644 /home/instore/logs/ProductMonitor_0.log
	failed $? "chmod ProductMonitor Log"
	chown -R instore:instore /home/instore/logs
	failed $? "chown instore logs dir"
	chown -R sck:sck $SCKHOME/*
	failed $? "chown sck home dir"
	[ -d /usr/local/apache-tomcat* ] && \
		chown -R sck:sck /usr/local/apache-tomcat*/ && \
		failed $? "chown tomcat dir"
	[ -d /opt/sqlanywhere* ] && \
		chown -R sck:sck /opt/sqlanywhere* && \
		failed $? "chown sybase dir"
	chmod -R 774 $SCKHOME/admin
	failed $? "chmod sck admin dir"
	chmod 744 /var/log/messages
	failed $? "chmod var log messages"
	[ -d $SCKHOME/sckengine ] && \
		chmod +x $SCKHOME/sckengine/bin/* && \
		failed $? "chmod sckengine bin directory"
	chmod a+rx /home/instore
	failed $? "chmod instore home dir"
}
makeImageVsInstall() {
	if [ "$machinetype" == "InputDevice" ] ; then
		configInputDevice
	fi
	if [ "$isimage" = "1" ] ; then
		configSite
	else
		configIPAddr
		touch $configimagefile
		echo "machinetype=$machinetype" > $configimagefile
		sed -i 's/id:5\(.*initdefault.*\)/id:3\1/' /etc/inittab
		failed $? "set init 3"
		$SCKHOME/admin/prepImage.sh
		failed 0 "This installation is for an image, so no specific configurations will be made at this time"
	fi
}

checkUpdate() {
	installfiletag=$(cat $installedverfile)
	installversion=( $(echo ${installfiletag##*[a-z][a-z]_} | sed 's/-/ /g') )
	installversionnum=$(echo ${installfiletag##*[a-z][a-z]_} | sed 's/-/./g')
	getfiles "$buildloc/$(basename $buildverfile)" "$SCKHOME/temp/" "rsync latest build version file"
	echo "Current version of SCK Software: " $installversionnum
	echo "Checking for update..."
	buildfiletag=$(cat $buildverfile)
	buildversion=( $(echo ${buildfiletag##*[a-z][a-z]_} | sed 's/-/ /g') )
	buildversionnum=$(echo ${buildfiletag##*[a-z][a-z]_} | sed 's/-/./g')
	update=0
	for (( i=0; i < ${#installversion[@]}; i++ ))
	do
		if [ ${installversion[$i]} -lt ${buildversion[$i]} ] ; then
			update=1
			break;
		elif [ ${installversion[$i]} -gt ${buildversion[$i]} ] ; then
			echo "The version of SCK Software on this machine is newer than the version that is currently available."			
			echo "exiting the update process."
			exit 1
		fi
	done
	if [ $update -eq 1 ] ; then
		echo "### An update is available for the SCK Software: version $buildversionnum ###"
		return 0
	else
		echo "The version of sck software on this machine is currently up to date."
		return 1
	fi
}

configSite() {
	checkSCKFile
	configIPAddr
	installFirewall
	[ "$machinetype" != "InputDevice" ] && configVideo
	configTimeZone
	if [ $update -ne 1 ] ; then
		configHostname
	fi
	if [ "$machinetype" != "InputDevice" ] ; then
		configDatabaseService
		configMobilink		
		configPOSSystem
		if [ $update -ne 1 ] ; then
			configDatabase
		else
			SYBASEENVCONFIG=$(find /opt -name '*sa_config.sh'| sort -r | head -1)
			(
			source $SYBASEENVCONFIG > /dev/null
			failed $? "Source Sybase script"
			#dbversion=$(dbisql -nogui -c "$sybaseconnstring" "select substring(@@version, 1, 2)" | sed -n '/^------*/{n;p;}' | sed 's/^[ \t]*//;s/[ \t]*$//')
			#echo $dbverion

            # if statement checks if theversion is 11 then..
            #if [$dbversion != 16]; then
			#   dbupgrad -nogui -c "$sybaseconnstring"
			#   failed $? "Running Upgrade of Sybase from 11 to 16"
			#fi
			dbisql -nogui -c "$sybaseconnstring" $SCKHOME/install/update.sql
			failed $? "Apply update.sql script"
			)
		fi
		getChainSite
	fi
	if [ "$machinetype" = "InputDevice" ] ; then
		installGenericSCKRestart
		promptInputDeviceInfo
	fi
	# editHomepage
	addToSCKSettingsFile
	sourceSCKSettings
	if [ "$machinetype" != "InputDevice" ] ; then
		modifySCKXMLSettings
	fi
	lockDownSystem
}

checkSCKFile() {
	preconfig="0"
	if [ $update -eq 1 ] ; then
		if [ -f $SCKHOME/SiteInfo.sck ] ; then
			source $SCKHOME/SiteInfo.sck
			preconfig="1"
		else
			[ -f $SCKHOME/SiteInfo.sck ] && rm -rf $SCKHOME/SiteInfo.sck
			touch $SCKHOME/SiteInfo.sck
		fi
	else
		[ -f $SCKHOME/SiteInfo.sck ] && rm -rf $SCKHOME/SiteInfo.sck
		touch $SCKHOME/SiteInfo.sck
	fi
}

configIPAddr() {
	configured="1"
	[ -f /etc/sysconfig/network-scripts/ifcfg-*.sav ] && rm -rf /etc/sysconfig/network-scripts/ifcfg-*.sav
	promptYesNo "Would you like to configure the IP Address information now" "y"
	if [ "$YESNO" = "y" ] ; then
		while [ "$configured" != "0" ]
		do
			if [ -z "$interface" ]; then
				echo "Please select the interface you would like to configure:"
				interfacelist=$(ip addr show | awk '{print $2}' | grep "eth*" | sed 's/://g')
				if [ $(echo "$interfacelist" | wc -w) -gt 1 ] ; then
					select interface in $interfacelist
					do
							if [ -n "$interface" ] ; then
								break
							fi
					done
				else
					interface=$(echo $interfacelist | head -1)
				fi
			fi
			echo "Using interface: ""$interface"
			[ -z "$iptype" ] && promptYesNo "Would you like to set a static IP Address" "y"
			if [ "$YESNO" = "y" ] || [ "$iptype" == "Static" ]; then
					iptype="Static"
					if [ -z "$newip" ]; then
						ip="$(ifconfig "$interface"| egrep "inet addr" | grep Bcast | awk '{ print $2 }' | awk -F ":" '{ print $2 }')"
						ipgood="1"
						while [ $ipgood != 0 ]
						do
							echo -n "Enter IP address [$ip]: "
							getInput "$ip"
							newip="$retdata"
							if valid_ip "$newip" ; then
								ipgood="0"
							else
								echo "Please enter a valid IP Address"
								ipgood="1"
							fi
						done
					fi
					if [ -z "$newnetmask" ] ; then
						netmask="$(ifconfig "$interface"| egrep "inet addr" | grep Bcast | awk '{ print $4 }' | awk -F ":" '{ print $2 }')"		
						ipgood="1"
						while [ $ipgood != 0 ]
						do
							echo -n "Enter Subnet Mask [$netmask]: "
							getInput "$netmask"
							newnetmask="$retdata"
							if valid_ip $newnetmask ; then
								ipgood="0"
							else
								echo "Please enter a valid Subnet Mask"
								ipgood="1"
							fi
						done
					fi
					if [ -z "$newdgateway" ] ; then
						dgateway="$(netstat -rn | awk '{ print $2 }' | tac | head -1)"
						ipgood="1"
						while [ $ipgood != 0 ]
						do
							echo -n "Default Gateway [$dgateway]: "
							getInput "$dgateway"
							newdgateway="$retdata"
							if valid_ip $newdgateway ; then
								ipgood="0"
							else
								echo "Please enter a valid Default Gateway"
								ipgood="1"
							fi
						done
					fi
					if [ -z "$newdns1" ] ; then
						dns1="$(cat /etc/resolv.conf | grep "nameserver " | awk '{ print $2 }' | head -1)"
						ipgood="1"
						while [ $ipgood != 0 ]
						do
							echo -n "Enter Primary DNS Server [$dns1]: "
							getInput "$dns1"
							newdns1="$retdata"
							if valid_ip $newdns1 ; then
								ipgood="0"
							else
								echo "Please enter a valid DNS Server"
								ipgood="1"
							fi
						done
					fi
					if [ -z "$newdns2" ] ; then
						dns2="$(cat /etc/resolv.conf | grep "nameserver " | awk '{ print $2 }' | tail -1)"
						ipgood="1"
						while [ $ipgood != 0 ]
						do
							echo -n "Enter Second DNS Server [$dns2]: "
							getInput "$dns2"
							newdns2="$retdata"
							if valid_ip $newdns2 ; then
								ipgood="0"
							else
								echo "Please enter a valid DNS Server"
								ipgood="1"
							fi
						done
					fi
			else
				echo "You have chose a Dynamic IP Address configuration"
				iptype="Dynamic"
				echo "Setting up Dynamic IP Address..."
			fi
			echo "------------------------------------------------"
			echo "Configuration"
			echo "------------------------------------------------"
			echo "Interface: 	" "$interface"
			if [ "$iptype" == "Static" ] ; then
				echo "IP Address Type: ""$iptype"
				echo "IP Address: 	""$newip"
				echo "Subnet Mask:	""$newnetmask"
				echo "Default Gateway:  ""$newdgateway"
				echo "DNS Server 1: ""$newdns1"
				echo "DNS Server 2: ""$newdns2"
			else
				echo "IP Address Type: ""$iptype"
			fi	
			echo "------------------------------------------------"
			promptYesNo "You have chosen a $iptype IP Address configuration, are these the correct settings" "y"
			if [ "$YESNO" = "y" ] ; then
				configured="0"
			else
				configured="2"
				unset interface iptype newip newnetmask newdgateway newdns1 newdns2
			fi
		done
		promptYesNo "Would you like to apply the changes you have made to the IP Address" "y"
		if [ "$YESNO" = "y" ] ; then
			cp /etc/sysconfig/network-scripts/ifcfg-${interface} $SCKHOME/admin/ifcfg-${interface}.sav
			if [ "$iptype" = "Dynamic" ] ; then
				{
				echo "# DHCP Configured by SCK Installation"
				echo "DEVICE=$interface"
				echo "BOOTPROTO=dhcp"
				echo "ONBOOT=yes"
				} > /etc/sysconfig/network-scripts/ifcfg-${interface}
			elif [ "$iptype" = "Static" ] ; then
				{
				echo "# Static IP Configured by SCK Installation"
				echo "DEVICE=$interface"
	        		echo "BOOTPROTO=static"
				echo "NETMASK=$newnetmask"
			        echo "IPADDR=$newip" 
				echo "GATEWAY=$newdgateway"
				echo "TYPE=Ethernet"
				echo "ONBOOT=yes"
				echo "USERCTL=no"
				echo "IPV6INIT=no"
				echo "PEERDNS=yes"
				echo "DNS1=$newdns1"
				echo "DNS2=$newdns2"
				} > /etc/sysconfig/network-scripts/ifcfg-${interface}
			else
				failed 1 "IP Configuartion Type unknown"
			fi
		else
			failed 0 "Not Appling changes"
		fi
		promptYesNo "Would you like to restart the network service now to make the changes take effect" "n"
		if [ "$YESNO" = "y" ] ; then
			service network restart
			failed $? "Restarting Network service"
		else
			echo "Please restart the machine for IP Address changes to take effect"
		fi
	else
		failed 0 "Skipping IP Address configuration"
	fi
}

getInput() {
	retdata=0
	read io
	if [ "$io" == "" ] ; then
		io="$1"
	fi
	retdata="$io"
	export retdata
	unset io
}
valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

configVideo() {
	if [ -z $xorgconfigused ] ; then
		if [ $interactive -eq 0 ] ; then
			if [ "$machinetype" != "InputDevice" ] ; then
				videocard=$(lspci | grep "VGA")
				if echo $videocard | grep -i "intel" > /dev/null ; then
					failed 0 "Detected Intel based Video Card."
					#Skipping this step for now
					#setupXorg "Intel"	
				elif echo $videocard | grep -i "nvidia" > /dev/null; then
					failed 0 "Detected nVidia based Video Card."
					yum -y install libXvMC
					failed 0 "Installing libXvMC"
					# Removing the old nvidia drivers if there to avoid conflicts
					rm -f nvidia-275.21-1.el5.elrepo.x86_64.rpm
					rm -f nvidia-x11-drv-275.21-1.el5.elrepo.x86_64.rpm
					# OK, now I can safely install the drivers
					rpm -ivh --force $SCKHOME/temp/nvidia*.rpm
					failed 0 "installing nvidia drivers"	
					setupXorg "Nvidia"
				elif echo $videocard | grep -i "ati" > /dev/null ; then
					failed 0 "Detected ati based Video Card."
					setupXorg "ATI"
				else
					failed 0 "Unable to detect supported Video Card."
					failed 0 "Not Configuring Xorg"
					xorgconfigused="NO_Xorg_Configured"
				fi
			else
				echo "Installing Intel based Xorg for Input Device"
				xorgconfigused="xorg.conf.Intel.Postouch1280x1024"
				[ -f /etc/X11/xorg.conf ] && cp /etc/X11/xorg.conf /etc/X11/xorg.conf.bak
				cp $SCKHOME/install/$xorgconfigused /etc/X11/xorg.conf
				failed $? "Copying customized Xorg.conf file"
			fi
		else
			xorgconfigused="NO_Xorg_Configured"
		fi
	fi
	if [ -z "$(grep "xorgconfigused" $SCKHOME/SiteInfo.sck)" ] ; then
		echo 'xorgconfigused='\"$xorgconfigused\" >> $SCKHOME/SiteInfo.sck
	else
		sed -i "s/\(xorgconfigused=\).*/\1$xorgconfigused/" $SCKHOME/SiteInfo.sck
		if [ $? -ne "0" ]; then
			echo 'xorgconfigused='\"$xorgconfigused\" >> $SCKHOME/SiteInfo.sck
		fi		
	fi
	if [ -z "$(grep "dpms" /etc/gdm/Init/Default)" ] ; then
		sed -i 's/\(exit 0\)/xset -dpms s off s noblank\n\1/' /etc/gdm/Init/Default
		failed $? "adding noblank to gnome"
	else
		sed -i 's/xset.*-dpms.*/xset -dpms s off s noblank/' /etc/gdm/Init/Default
		failed $? "modifing gnome to noblank"
	fi
}

setupXorg() {
	videocardmanu="$1"
	xorglist=$(ls $SCKHOME/install/ | grep "xorg.conf" | grep "$videocardmanu" | awk -F. '{print $NF}')
	xorglist="$xorglist NO_Xorg_Configured"
	echo "Please Select Xorg configuration to use..."
	select name in $(echo $xorglist | sed 's/ /\n/g')
	do
		if [ -n "$name" ] ; then
			if [ "$name" != "NO_Xorg_Configured" ] ; then
				xorgconfigused="xorg.conf.$videocardmanu.$name"
			else
				xorgconfigused="NO_Xorg_Configured"
			fi
			break
		fi
	done
	echo "Using Xorg.conf file $xorgconfigused"
	if ! $(echo "$xorgconfigused" | grep "NO_Xorg_Configured" > /dev/null) ; then
		[ -f /etc/X11/xorg.conf ] && cp /etc/X11/xorg.conf /etc/X11/xorg.conf.bak
		cp $SCKHOME/install/$xorgconfigused /etc/X11/xorg.conf
		failed $? "Copying customized Xorg.conf file"
	fi
	}

configInputDevice() {
	installIDDrivers
	configVideo
}

installIDDrivers() {
	tar xf $SCKHOME/temp/inputdevicedrivers.tgz -C $SCKHOME/temp/
	failed $? "Extracting input device drivers"
	cd $SCKHOME/temp/inputdevicedrivers/
	failed $? "cd into input device driver directory"
	./install.sh
	failed $? "run input device driver setup"
	mkdir -p $SCKHOME/.config/autostart/
	failed $? "mkdir config/autostart/ for sck user"
	{
	echo '[Desktop Entry]'
	echo 'Version=1.0'
	echo 'Type=Application'
	echo 'Encoding=UTF-8'	
	echo 'Name=Touchscreen calibration'
	echo 'GenericName=Touchscreen'
	echo 'Comment=This application will calibrate Touchscreen'
	echo 'TryExec=Linear232'
	echo 'Exec=Linear232 /dev/ttyS0 9'
	echo 'Terminal=false'
	echo 'StartupNotify=false'
	echo 'Hidden=false'
	} > $SCKHOME/.config/autostart/touchscreencalib.desktop
	failed $? "Writing touchscreencalib autostart file"

}

installGenericSCKRestart() {
	setInit sckrestart -n
	failed $? "Install sckrestart init.d script"
	errors=1
	while [ $errors != 0 ]
	do
		promptYesNo "Would you like to change the screen restart time" "n"
        	if [ "$YESNO" = "y" ] ; then
			echo -n "Please enter the hour you wish to restart the screen (24 hour): " 
			read restartHr
			echo
			echo -n "Please enter the minutes past the hour you wish to restart the screen(leading zero on single digit required): "
			read restartMin
		else
			restartHr=7
			restartMin=10
		fi
		echo "restart at "$restartHr":"$restartMin
		for minslice in $(echo "$restartMin" | sed 's/[,-]/ /g') ; do
			if ! validNum $minslice 60 ; then
		      		echo "Invalid minute value \"$minslice\""
				errors=1
			else 
				errors=0
		    	fi
		done
		# hour check
		for hrslice in $(echo "$restartHr" | sed 's/[,-]/ /g') ; do
			if ! validNum $hrslice 24 ; then
				echo "Invalid hour value \"$hrslice\"" 
				errors=1
			else 
				errors=0
		   	fi
		done
	done
	rm -rf /etc/cron.d/sckrestart
	echo "$restartMin $restartHr" '* * *' "root /etc/init.d/sckrestart" > /etc/cron.d/sckrestart
	chmod 644 /etc/cron.d/sckrestart
	chown root:root /etc/cron.d/sckrestart
}

validNum()
{
  # return 0 if valid, 1 if not. Specify number and maxvalue as args
  num=$1   max=$2

  if [ "$num" = "X" ] ; then
    return 0
  elif [ ! -z $(echo $num | sed 's/[[:digit:]]//g') ] ; then
    return 1
  elif [ $num -lt 0 -o $num -gt $max ] ; then
    return 1
  else
    return 0
  fi
}
configTimeZone() {
    curTz=`date +"%Z (%z)"`
	promptYesNo "Would you like to configure the time zone to be different from the current time zone of $curTz" "n"
	if [ "$YESNO" = "y" ] ; then
		$SCKHOME/install/timeconfig.sh
	fi
}

configHostname() {
	if [ -z $usehostname ] ; then
		if [ $interactive -eq 0 ] ; then
			verifyCorrect "Hostname" "$(hostname | cut -d. -f1)"
			usehostname="$RETDATA"
		else
			usehostname=""
		fi
	fi
	if [ "$usehostname" != "" ]; then
	     	echo "New Hostname is: $usehostname"
		sed -i "s/\(127.0.0.1.*\)/\1 $usehostname INSTOREDB/" /etc/hosts
		failed $? "setting hostname in hosts file"
		sed -i "s/\(HOSTNAME=\).*/\1$usehostname/" /etc/sysconfig/network
		failed $? "setting hostname in sysconfig/network file"
		hostname $usehostname
		failed $? "setting hostname with hostname command"
	else
		echo "Using current hostname: $(hostname | cut -d. -f1)"
		if [ -z "$(grep "INSTOREDB" /etc/hosts)" ] ; then 
			sed -i "s/\(127.0.0.1.*\)/\1 INSTOREDB/" /etc/hosts
		fi
	fi
}

configDatabaseService() {
	if [ -z $sybasedbname ] ; then
        	sybasedbname="$usehostname"
	        if [ $interactive -eq 0 ] ; then
        	        verifyCorrect "Database Name" "$sybasedbname"
	                sybasedbname="$RETDATA"
        	fi
	fi
	echo "Database Server name is:" $sybasedbname
	sed -i "s/\(SYBASEDBNAME=\).*/\1$sybasedbname/" /etc/init.d/scksybase
	sed -i "/sybasedbname=.*/d" $SCKHOME/SiteInfo.sck
	echo 'sybasedbname='\"$sybasedbname\" >> $SCKHOME/SiteInfo.sck
	/etc/init.d/scksybase restart
	failed $? "starting sybase"	
}

configMobilink() {
	if [ $update -eq 1 ] ; then
		SQLFILE=$SCKHOME/install/update.sql
		[ ! -z "$SQLFILE" ] && failed $? "Find SQL file"
		SYBASEENVCONFIG=$(find /opt -name '*sa_config.sh'| sort -r | head -1)
        	source $SYBASEENVCONFIG > /dev/null
		mlsyncid=$(dbisql -nogui -c "eng=unspecified;uid=kfcfran;pwd=colonel;links=tcpip{IP=INSTOREDB,Port=2638;verify=no;dobroadcast=none}" "SELECT MAX(site_name)FROM SYSSYNCUSERS" | sed -n '/^------*/{n;p;}' | sed 's/^[ \t]*//;s/[ \t]*$//')
		mlsyncserver=$(dbisql -nogui -c "eng=unspecified;uid=kfcfran;pwd=colonel;links=tcpip{IP=INSTOREDB,Port=2638;verify=no;dobroadcast=none}" "Select server_connect From SYS.SYSSYNCSUBSCRIPTIONS Where publication_name='MySCK_KfcUsFran';" | sed -n '/^------*/{n;p;}' | sed 's/^[ \t]*//;s/[ \t]*$//' | sed 's/host=\(.*\);port.*/\1/')
	else
		SQLFILE=$(find $SCKHOME/install -maxdepth 1 -name "MySCK_KfcUsFran_remote.sql")
		[ ! -z "$SQLFILE" ] 
		failed $? "Find SQL file"
	fi
	if [ -z $mlsyncid ] ; then
		mlsyncid="***NONE***"
		verifyCorrect "Mobilink SyncID" "$mlsyncid"
        	mlsyncid="$RETDATA"
	else
		echo "Mobilink Sync ID is:" $mlsyncid
	fi
	if [ -z $mlsyncserver ] ; then
		mlsyncserver="127.0.0.1"
		verifyDefault "Mobilink Sync Server" "$mlsyncserver"
		mlsyncserver="$RETDATA"
	else
		verifyDefault "Mobilink Sync Server" "$mlsyncserver"
		mlsyncserver="$RETDATA"
	fi
	if [ "$mlsyncserver" = "messaging.mysck.net" ] ; then
		promptYesNo "WARNING: This installation will connect to the Live Production Site, are you sure you want to do this?" "y"
		if [ "$YESNO" = "n" ] ; then
			failed 1 "Chose NO to connect to the Live Production Site"
		else
			failed 0 "Chose Yes to connect to the Live Production Site"
		fi
	fi
	if [ $update -ne 1 ] ; then
		sed -e "s/ML_USER/$mlsyncid/g" -e "s/ML_PASSWORD/$mlsyncid/g" -e "s/\(host=\).*\(;port=.*\)/\1$mlsyncserver\2/g" $SQLFILE > $SCKHOME/install/instoredb.sql
	fi
	sed -i -e "s/ML_USER/$mlsyncid/g" -e "s/ML_PASSWORD/$mlsyncid/g" -e "s/\(host=\).*\(;port=.*\)/\1$mlsyncserver\2/g" $SCKHOME/install/update.sql
	if [ "$preconfig" == "0" ] ; then
		echo 'mlsyncid='\"$mlsyncid\" >> $SCKHOME/SiteInfo.sck
		echo 'mlsyncserver='\"$mlsyncserver\" >> $SCKHOME/SiteInfo.sck
	else
		sed -i "s/\(mlsyncid=\).*/\1$mlsyncid/" $SCKHOME/SiteInfo.sck
		if [ $? -ne "0" ]; then
			echo 'mlsyncid='\"$mlsyncid\" >> $SCKHOME/SiteInfo.sck
		fi
		sed -i "s/\(mlsyncserver=\).*/\1$mlsyncserver/" $SCKHOME/SiteInfo.sck
		if [ $? -ne "0" ]; then
			echo 'mlsyncserver='\"$mlsyncserver\" >> $SCKHOME/SiteInfo.sck
		fi		
	fi
}

configPOSSystem() {
	if [ -z $possystem ] ; then
		possystemlist=$(grep '<!--' $SCKHOME/sckengine/config/springConfig.xml | egrep 'POSSystem' | awk '{print $2}')
		possystemlist="$possystemlist NO_POS_CONFIGURED"
		echo "Please select the POS System to use..."
		select name in $(echo $possystemlist | sed 's/ /\n/g' | uniq)
		do  
			possystem=$name
		       	if [ -n "$name" ] ; then 
				break
			fi
		done
	fi
	echo "Setting POS System to $possystem"
	if [ -z "$(grep "possystem=" $SCKHOME/SiteInfo.sck)" ] ; then
		echo "possystem=\"$possystem\"" >> $SCKHOME/SiteInfo.sck
	else
		sed -i "s/\(POSSYSTEM=\).*/\1$possystem/g" $SCKHOME/SiteInfo.sck
	fi
}

configDatabase() {
	SYBASEENVCONFIG=$(find /opt -name '*sa_config.sh'| sort -r | head -1)
	(
	source $SYBASEENVCONFIG > /dev/null
	failed $? "Source Sybase script"
	dbisql -nogui -c "$sybaseconnstring" $SCKHOME/install/instoredb.sql
	failed $? "Apply sql script"
	dbmlsync -pi -c "$sybaseconnstring"
	failed $? " Testing Connection to Mobilink Server and Mobilink Sync ID"
	)
	failed $? "SQL Script Apply"
	$SCKHOME/admin/mobilinkonetime.sh
	failed $? "First Mobilink sync"
}

getChainSite() {
	(
	source $SYBASEENVCONFIG > /dev/null
	failed $? "Source Sybase script"
	source $SCKHOME/SiteInfo.sck
	failed $? "Source SiteInfo.sck file"
	if [ -z $SYBASECHAINID ] ; then
		SYBASECHAINID=$(dbisql -nogui -c "$sybaseconnstring" "select chainid from $sybaseusername.chains" | sed -n '/^------*/{n;p;}' | sed 's/^[ \t]*//;s/[ \t]*$//')
		failed $? "Get ChainID from database"
		echo 'SYBASECHAINID='\"$SYBASECHAINID\" >> $SCKHOME/SiteInfo.sck
		failed $? "Write ChainId to SiteInfo.sck file"		
	fi
	if [ -z "$SYBASECHAINNAME" ] ; then
		SYBASECHAINNAME=$(dbisql -nogui -c "$sybaseconnstring" "select chainname from $sybaseusername.chains" | sed -n '/^------*/{n;p;}' |sed 's/^[ \t]*//;s/[ \t]*$//')
		failed $? "Get ChainName from database"
		echo 'SYBASECHAINNAME='\"$SYBASECHAINNAME\" >> $SCKHOME/SiteInfo.sck
		failed $? "Write ChainName to SiteInfo.sck file"
	fi
	if [ -z $SYBASESITEID ] ; then
		SYBASESITEID=$(dbisql -nogui -c "$sybaseconnstring" "select siteid from $sybaseusername.sites where Chainid=$SYBASECHAINID and SiteId !=0" | sed -n '/^------*/{n;p;}' | sed 's/^[ \t]*//;s/[ \t]*$//')
		failed $? "Get SiteID from database"
		echo 'SYBASESITEID='\"$SYBASESITEID\" >> $SCKHOME/SiteInfo.sck
		failed $? "Write SiteID to SiteInfo.sck file" 
	fi
	if [ -z "$SYBASESITENAME" ] ; then
		SYBASESITENAME=$(dbisql -nogui -c "$sybaseconnstring" "select sitename from $sybaseusername.sites where Chainid=$SYBASECHAINID and SiteId !=0" | sed -n '/^------*/{n;p;}' | sed 's/^[ \t]*//;s/[ \t]*$//')
		failed $? "Get SiteName from database"
		echo 'SYBASESITENAME='\"$SYBASESITENAME\" >> $SCKHOME/SiteInfo.sck
		failed $? "Write SiteName to SiteInfo.sck file"
	fi
	)
}

addToSCKSettingsFile() {
	sed -i "/TOMCATPOWERDSCKLOC=.*/d" $SCKHOME/SiteInfo.sck 
	echo "TOMCATPOWERDSCKLOC=\"http://localhost:8080/instore/images/powerd_sck.gif\"" >> $SCKHOME/SiteInfo.sck
	chown sck:sck $SCKHOME/SiteInfo.sck
	failed $? "chown SiteInfo.sck"
	cp -p $SCKHOME/SiteInfo.sck $SCKHOME/install/SiteInfo.sck
}

sourceSCKSettings() {
	source $SCKHOME/SiteInfo.sck
	failed $? "Source SiteInfo.sck"
	if [ -n "$SYBASECHAINNAME" ] ; then
		echo "[Chain is: $SYBASECHAINNAME]"
		promptYesNo "Is this the correct Chain?" "y"
		if [ "$YESNO" = "n" ] ; then
			failed 1 "Correct Chain"
		fi
		echo "[Site is: $SYBASESITENAME]"
		promptYesNo "Is this the correct Site?" "y"
		if [ "$YESNO" = "n" ] ; then
			failed 1 "Correct Site"
		fi
	fi
}

modifySCKXMLSettings() {
	CONFFILES="$SCKHOME/sckengine/config/SCKEngineConfig.xml $SCKHOME/sckengine/config/springConfig.xml" 
	for FILE in $CONFFILES
	do
		sed -i "s/\(<chainid>\).*\(<\/chainid>\)/\1$SYBASECHAINID\2/g; s/\(<siteid>\).*\(<\/siteid>\)/\1$SYBASESITEID\2/g" $FILE
		sed -i "s/\(<property name=\"chainId\"><value>\).*\(<\/value><\/property>\)/\1$SYBASECHAINID\2/g; s/\(<property name=\"siteId\"><value>\).*\(<\/value><\/property>\)/\1$SYBASESITEID\2/g" $FILE
		sed -i -e '
		'/.*\<!--.*chainId.*--\>/' {
		# found a line that matches
		# add the next line to the pattern space
		N
		# exchange the previous line with the 
		# 2 in pattern space
		x
		# now add the two lines back
		g
		# and print it.	
		# add the three hyphens as a marker
		# remove first 2 lines
	        s@\(/*<value>\).*\(<.*value>\)@\1'$SYBASECHAINID'\2@g
		# and place in the hold buffer for next time
		h
		}' $FILE 
		sed -i "s/\(<!-- $possystem\)[\t]*/\1 START -->/g; s/$possystem\( -->\)[\t]*/<!-- $possystem END \1/g" $FILE
	done
}

lockDownSystem() {
promptYesNo "Would you like to lock down this installation?" "y"
	if [ "$YESNO" = "y" ] ; then
		echo "Locking down the system"
		sed -i -e 's/#\(PermitRootLogin\).*/\1 no/' -e 's/^\(PermitRootLogin\).*/\1 no/' /etc/ssh/sshd_config
		failed $? "Disabling root user ssh login"
		if [ -z "$(grep "DenyUsers" /etc/ssh/sshd_config)" ] ; then
			sed -i 's/.*\(DenyUsers\).*/\1 instore/' /etc/ssh/sshd_config
			failed $? "Disabling instore user ssh login"
		else
			echo "DenyUsers instore" >> /etc/ssh/sshd_config
			failed $? "Disabling instore user ssh login"
		fi
		if [ -z "$(grep 'umask' /etc/profile)" ]
		then
			echo --- set default umask to 077
			echo umask 077 >> /etc/profile
			failed $? "umask /etc/profile"
			echo umask 077 >> /etc/bashrc
			failed $? "umask /etc/bashrc"
			echo umask 077 >> /etc/csh.cshrc
			failed $? "umask /etc/csh.cshrc"
			echo umask 077 >> /root/.bashrc
			failed $? "umask /root/.bashrc"
			echo umask 077 >> /root/.bash_profile
			failed $? "umask /root/.bash_profile"
			echo umask 077 >> /root/.cshrc
			failed $? "umask /root/.cshrc"
			echo umask 077 >> /root/.tcshrc
			failed $? "umask /root/.tcshrc"
		fi
		if [ -z "$(grep '~~:S:wait:/sbin/sulogin' /etc/inittab)" ] ; then
			echo --- require root password for single user mode
			echo ~~:S:wait:/sbin/sulogin >> /etc/inittab
			failed $? "root password for init 1"
		fi
		if [ -z "$(egrep 'prompt|PROMPT' /etc/sysconfig/init)" ] ; then
			echo --- disable interactive boot
			echo PROMPT=no >> /etc/sysconfig/init	
			failed $? "no interactive boot"
		else
			sed -i 's/[pP][rR][oO][mM][pP][tT]=.*/PROMPT=no/' /etc/sysconfig/init
			failed $? "disabling interactive boot"
		fi
		if [ -z "$(grep umask /etc/sysconfig/init)" ] ; then
			echo umask 027 >> /etc/sysconfig/init
			failed $? "umask /etc/sysconfig/init"
		fi
		echo disabling core dumps
		chkconfig kdump off
		if [ -z "$(grep 'hard core 0' /etc/security/limits.conf)" ] ; then
			echo '*	hard core 0' >> /etc/security/limits.conf
			failed $? "modify /etc/security/limits.conf"
		fi
		if [ -z "$(grep 'fs.suid_dumpable = 0' /etc/sysctl.conf)" ] ; then
			{
			echo fs.suid_dumpable = 0
			echo kernel.exec-shield = 1
			echo kernel.randomize_va_space = 1 
			} >> /etc/sysctl.conf
			failed $? "modify /etc/sysctl.conf"
		fi
	fi
}

installFirewall() {
	rpm --nosignature --nodeps --force -Uvh $SCKHOME/install/apf*
	[ -f $(which apf 2&>1 > /dev/null) ]
	failed $? "installing apf firewall"
	[ ! -f /usr/local/sbin/apf ] && ln -s /usr/sbin/apf /usr/local/sbin/apf
	failed 0 "symlink for apf so init scripts work"
	if [ "$machinetype" == "KitchenAdvisor" ] ; then
		verifyDefault "VNC Port" "$kavncport"
		vncport=$RETDATA
		verifyDefault "SSH Port" "$kasshport"
		sshport=$RETDATA
		cp $SCKHOME/install/conf.apf.ka /etc/apf/conf.apf
		failed $? "copy conf.apf"
		if [ -z "$(grep "to-ports 8080" /etc/apf/preroute.rules)" ] ; then
			echo "iptables -t nat -A PREROUTING -p tcp --dport $kawebport -j REDIRECT --to-ports 8080" >> /etc/apf/preroute.rules
		else
			sed -i "s/^.*--to-ports 8080/iptables -t nat -A PREROUTING -p tcp --dport $kawebport -j REDIRECT --to-ports 8080/" /etc/apf/preroute.rules
		fi
		if [ -z "$(grep "sport 2362" /etc/apf/preroute.rules)" ] ; then
			echo "iptables -I INPUT -p udp --sport 2362 -j ACCEPT" >> /etc/apf/preroute.rules
		else
			sed -i "s/^.*--sport 2362/iptables -I INPUT -p udp --sport 2362 -j ACCEPT/" /etc/apf/preroute.rules
		fi
		if [ -z "$(grep "dport 8081" /etc/apf/preroute.rules)" ] ; then
			echo "iptables -I INPUT -p tcp --dport 8081 -j ACCEPT" >> /etc/apf/preroute.rules
		else
			sed -i "s/^.*--dport 8081/iptables -I INPUT -p tcp --dport 8081 -j ACCEPT/" /etc/apf/preroute.rules
		fi
	elif [ "$machinetype" == "InputDevice" ] ; then
		verifyDefault "VNC Port" "$idvncport"
		vncport=$RETDATA
		verifyDefault "SSH Port" "$idsshport"
		sshport=$RETDATA
		cp $SCKHOME/install/conf.apf.id /etc/apf/conf.apf
		failed $? "copy conf.apf"
	fi
	if [ -z "$(grep "to-ports 5900" /etc/apf/preroute.rules)" ] ; then
		echo "iptables -t nat -A PREROUTING -p tcp --dport $vncport -j REDIRECT --to-ports 5900" >> /etc/apf/preroute.rules
	else
		sed -i "s/^.*--to-ports 5900/iptables -t nat -A PREROUTING -p tcp --dport $vncport -j REDIRECT --to-ports 5900/" /etc/apf/preroute.rules
	fi
	if [ "$sshport" != "22" ] ; then
		if [ -z "$(grep "to-ports 22" /etc/apf/preroute.rules)" ] ; then
			echo "iptables -t nat -A PREROUTING -p tcp --dport $sshport -j REDIRECT --to-ports 22" >> /etc/apf/preroute.rules
		else
			sed -i "s/^.*--to-ports 22/iptables -t nat -A PREROUTING -p tcp --dport $sshport -j REDIRECT --to-ports 22/" /etc/apf/preroute.rules
		fi
	fi

}

setInit () {
   # Get Name of service
   NAME=$1 ; shift
   # Get CHKCONFIG parameter
   CHKCONFIG=$1 ; shift
   
   # Copy service NAME to /etc/init.d directory
   cp $SCKHOME/install/$NAME /etc/init.d
   # Change owner to root
   chown root:root /etc/init.d/$NAME
   # Change mode rights to rwxr-xr-x
   chmod 755 /etc/init.d/$NAME
   # Run CHKCONFIG to enable service to run at startup if -n parameter is not passed
   if [ "$CHKCONFIG" != "-n" ]; then
      chkconfig --add $NAME
   fi
}

failed() {
	if [ "$1" -ne 0 ] ; then
		echo "$2 failed. INSTALLATION FAILED! Exiting.";
		exit 1;
	fi
	echo "$2 Done"
}

verifyCorrect() {
	iscorrect=1
	RETDATA=""
	propname="$1"
	propvalue="$2"
	echo "Default $propname:" "$propvalue"
        echo "Please enter the" "$propname" "you would like to use or hit Enter to use default"
        read -a propvalue
        while [ "$iscorrect" -eq "1" ]
        do
                if [ -z $propvalue ] ; then
			propvalue=$2
		fi
		echo "Using" "$propname" "$propvalue"
                promptYesNo "Is this correct?" "y"
                if [ "$YESNO" = "y" ] ; then
                        iscorrect=0
                        RETDATA="$propvalue"
                else
                        echo  "Please enter the" "$propname" "you would like to use"
                        read -a propvalue
                fi
        done
	export RETDATA
	unset propname
	unset propvalue
	return 0
}


getfiles() {
	if type rsync > /dev/null 2>&1 ; then
		failed 0 "rsync installed"
	else
		yum clean all
		failed $? "yum clean"
		yum -y install rsync
		failed $? "rsync installed"
	fi	
	rsyncsource=$1
	rsyncdest=$2
	rsyncmsg=$3
	if [ ! -z $4 ] ; then
		rsyncexclude=$4
	else
		rsyncexclude=""
	fi
	declare -i retrycount
	retval=1
	echo $rsyncpw > $rsyncpwfile
	chmod 600 $rsyncpwfile
	rsync -aczh --exclude="$rsyncexclude" --timeout=60 --password-file=$rsyncpwfile --stats --progress $buildcred@$buildserver::$rsyncsource $rsyncdest
	retval=$?
	rm $rsyncpwfile
	return $retval
}

promptYesNo() {
	if [ $# -lt 1 ] ; then
		failed 1 "Insufficient Arguments."
		return 1
	fi
	DEF_ARG=""
	YESNO=""
	case "$2" in
		[yY]|[yY][eE][sS])
			DEF_ARG=y ;;
		[nN]|[nN][oO])
			DEF_ARG=n ;;
	esac
	if [ $interactive -eq 0 ] ; then
		while :
		do
			echo "$1 (y/n)? "
			if [ -n "$DEF_ARG" ] ; then
				printf "[$DEF_ARG] "
			fi
			read YESNO
			if [ -z "$YESNO" ] ; then
				YESNO="$DEF_ARG"
			fi
			case "$YESNO" in
				[yY]|[yY][eE][sS])
					YESNO=y ; break ;;
				[nN]|[nN][oO])
					YESNO=n ; break ;;
				*)
					YESNO="" ;;
			esac
		done
	else
		YESNO="$DEF_ARG"
	fi
	export YESNO
	unset DEF_ARG
	return 0
}

verifyDefault() {
	iscorrect=1
	RETDATA=""
	propname="$1"
	propvalue="$2"
	promptYesNo "Would you like to use the default $propname: $propvalue" "y"
	if [ "$YESNO" = "y" ] ; then
        	iscorrect=0
                RETDATA="$propvalue"
        else
		echo "Default $propname:" "$propvalue"
                echo  "Please enter the" "$propname" "you would like to use"
                read -a propvalue
		while [ "$iscorrect" -eq "1" ]
	        do
        	        if [ -z $propvalue ] ; then
				propvalue=$2
			fi
			echo "Using" "$propname" "$propvalue"
	                promptYesNo "Is this correct?" "y"
	                if [ "$YESNO" = "y" ] ; then
        	                iscorrect=0
	                        RETDATA="$propvalue"
	                else
	                        echo  "Please enter the" "$propname" "you would like to use"
	                        read -a propvalue
        	        fi
	        done
        fi
	export RETDATA
	unset propname
	unset propvalue
	return 0
}

#############
# Variables #
#############
alias cp='cp'
alias rm='rm'
alias mv='mv'

mlsyncserver=""
mlsyncid=""
sybasedbname=""
possystem=""
usehostname=""
configimagefile="/.sckimageon"
interactive=0
xorgconfigused=""
rsyncpw="5am1am"
rsyncpwfile="/root/rsync.passwd"
buildserver="sckbuild.fastinc.com"
buildcred="sckadmin"
buildlist="QA Staging Production"
stagingloc="staging/environment/instorecentos6/"
qaloc="latestqa"
stagloc="lateststaging"
prodloc="latest"
tomcatarc="apache-tomcat-6.0.18.tar.gz"
SCKHOME="/home/sck"
sybaseusername="kfcfran"
sybasepasswd="colonel"
sybaseport="2638"
sybaseconnstring="eng=unspecified;uid=$sybaseusername;pwd=$sybasepasswd;links=tcpip{IP=INSTOREDB,Port=$sybaseport;verify=no;dobroadcast=none}"
kaipaddress="INSTOREDB:8080"
excludepackages="java*openjdk"
fullInstall=0
update=0
installedverfile="$SCKHOME/installedversion"
buildverfile="$SCKHOME/temp/buildVersion.txt"
machinetypes="KitchenAdvisor InputDevice"
kavncport="5901"
idvncport="5900"
kasshport="22"
idsshport="2222"
kawebport="80"

########
# main #
########
#set -x # script debuging
{
#Get Arguments
getArgs "${@}"
#Check that the system is ready for an installation/upgrade
preinstallCheck
# Prepare the process by stopping all SCK services if installed
prepareProcess
# Prompt and Check for OS updates
updateOS
# Check if installation is an image
checkIfImage
# Prompt for Environment SCK Software will be used in
promptEnv
# Set Environment that will be used
setEnv
# Prompt user to select which Machine Type the installation is on
promptMachineType
# Prompt if this will be an image installation
promptImage
# Check if a version of SCK Software had been installed and ask to update
updateSCK
# Install Update or fresh installation
if [ $fullInstall -eq 1 ] ; then
	# Install OS included Packages and mask off unwanted packages
	installOSPackages
	# Disable all unwanted services
	disableServices
	# Make neccessary changes to OS settings
	changeOSSettings
	# Create SCK user accounts and passwords
	addUsers
	# Get SCK Software from build server
	getSCKPackages
	# Install SCK Software Packages
	installSCKPackages
	if [ "$machinetype" != "InputDevice" ] ; then
		#Install New Database
		installFreshDB
		# Install SCK Service Init scripts
		installSCKInitScripts
		# Install SCK Administrative scripts and files
		installSCKAdminScripts
	fi
	# Configure the Instore user GUI and Desktop Profile
	configInstoreDesktop
	#Create Needs Directories and Fix file permissions
	createDirsFixPermissions
	# If image, set IP and exit. If not image, config Site
	makeImageVsInstall
elif [ $update -eq 1 ] ; then
	if [ "$machinetype" != "InputDevice" ] ; then
		/etc/init.d/scksybase restart
		failed $? "Starting up SCK Database service"
		sleep 5
		$SCKHOME/admin/mobilinkonetime.sh
		failed $? "Performing Mobilink sync before proceeding with upgrade"
	fi
	# Install OS included Packages and mask off unwanted packages
	installOSPackages
	# Disable all unwanted services
	disableServices
	# Make neccessary changes to OS settings
	changeOSSettings
	# Create SCK user accounts and passwords
	addUsers
	# Get SCK Software from build server
	getSCKPackages
	# Install SCK Software Packages
	installSCKPackages
	if [ "$machinetype" != "InputDevice" ] ; then
		# Install SCK Service Init scripts
		installSCKInitScripts
		# Install SCK Administrative scripts and files
		installSCKAdminScripts
	fi
	# Configure the Instore user GUI and Desktop Profile
	configInstoreDesktop
	# Create Needs Directories and Fix file permissions
	createDirsFixPermissions
	# If Image, set IP and exit. If not image, config Site
	makeImageVsInstall
	$SCKHOME/admin/mobilinkonetime.sh
	failed $? "Mobilink sync to pull down data after upgrade"
else 
	exit 0
fi
# I'm getting rid of the old CentOS 5 sckrestart with this new one
rm /etc/init.d/sckrestart
cp $SCKHOME/install/sckrestart6 /etc/init.d/sckrestart
chmod 755 /etc/init.d/sckrestart
cp $SCKHOME/temp/buildVersion.txt $SCKHOME/installedversion
cat $SCKHOME/installedversion > /etc/sckrelease
chown -R sck:sck $SCKHOME/
chown -R instore:instore /home/instore/
failed 0 "--- Congratulations! Installation complete at $(date)"
} | tee -a SCKInstallation.log 
