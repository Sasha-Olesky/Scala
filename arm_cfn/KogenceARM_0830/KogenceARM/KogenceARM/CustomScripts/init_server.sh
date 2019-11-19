# Custom Script for Linux

STACK_NAME="sandbox";
REGION_NAME="Central US";
PORXY_SERVER="http://localhost/"
proxy=$PORXY_SERVER

custom_cookbook="NONE"
cookbook_url="NONE"

kogenceclusterversion="kogencecluster-1.4.2"
kogenceclustercookbookversion="kogencecluster-cookbook-1.4.1"
kogenceclusterchefversion="12.19.36"
kogenceclusterridleyversion="5.1.0"
kogenceclusterberkshelfversion="5.6.4"

PreInstallScript="NONE"
PreInstallArgs="NONE"
PostInstallScript="NONE"
PostInstallArgs="NONE"
Scheduler="sge" #AllowedValues: [sge, torque, slurm, custom, test]
EncryptedEphemeral="true" #AllowedValues: [true, false]
EphemeralDir="/scratch"
SharedDir="/shared"
OSUser="ubuntu" # default OS ubuntu1404
DynamoDBTable="NONE" # DynamoDBTable name
QueueName="NONE" # QueueName
CustomChefRunList="NONE"
ExtraJson="{}"

function error_exit{
	kogence-signal ${proxy_args} --exit-code=1 --reason=\"$1\" --stack=$STACK_NAME --resource=MasterServer --region=$REGION_NAME;
	exit 1;
}

function bootstrap_instance{
	which yum 2>/dev/null; yum=$?;
	which apt-get 2>/dev/null; apt=$?;
	if [ \"$yum\" == \"0\" ]; then
		yum -y groupinstall development && yum -y install curl wget;
	fi
	if [ \"$apt\" == \"0\" ]; then
		apt-cache search build-essential; apt-get clean; apt-get update; apt-get -y install build-essential curl wget
	fi
	which kogence-init 2>/dev/null || ( curl -s -L -o /tmp/aws-kogence-bootstrap-latest.tar.gz https://s3.amazonaws.com/cloudformation-examples/aws-kogence-bootstrap-latest.tar.gz; easy_install -U /tmp/aws-kogence-bootstrap-latest.tar.gz);
	mkdir -p /etc/chef && chown -R root:root /etc/chef;
	curl -L https://www.chef.io/chef/install.sh | bash -s -- -v $chef_version;
	/opt/chef/embedded/bin/gem install --no-rdoc --no-ri ridley:$ridley_version berkshelf:$berkshelf_version;
	curl -s -L -o /etc/chef/kogencecluster-cookbook.tgz $cookbook_url;
	curl -s -L -o /etc/chef/kogencecluster-cookbook.tgz.date $cookbook_url.date;
	curl -s -L -o /etc/chef/kogencecluster-cookbook.tgz.md5 $cookbook_url.md5;
	mkdir /opt/kogencecluster && echo $kogencecluster_version | tee /opt/kogencecluster/.bootstrapped;
}

function setting_config() {
	ProxyServer=$1;
	which yum && echo $PORXY_SERVER >> /etc/yum.conf
	which apt-get && echo "Acquire::http::Proxy \"$PORXY_SERVER\";" >> /etc/apt/apt.conf

	if [ \"$proxy\" != \"NONE\" ]; then
		proxy_args=\"--http-proxy=${proxy} --https-proxy=${proxy}\";
		proxy_host=$(echo \"$proxy\" | awk -F/ '{print $3}' | cut -d: -f1);
		proxy_port=$(echo \"$proxy\" | awk -F/ '{print $3}' | cut -d: -f2);
		export http_proxy=$proxy; export https_proxy=$http_proxy;
		export HTTP_PROXY=$proxy; export HTTPS_PROXY=$http_proxy;
		export no_proxy=169.254.169.254; export NO_PROXY=169.254.169.254;
		echo -e \"export http_proxy=$proxy; export https_proxy=$http_proxy\nexport HTTP_PROXY=$proxy; export HTTPS_PROXY=$http_proxy\nexport no_proxy=169.254.169.254; export NO_PROXY=169.254.169.254\n\" >/tmp/proxy.sh;
		echo -e \"[Boto]\nproxy = ${proxy_host}\nproxy_port = ${proxy_port}\n\" >/etc/boto.cfg;
	else
		proxy_args=\"\";
		touch /tmp/proxy.sh;
	fi

	if [ \"$custom_cookbook\" != \"NONE\" ]; then
		cookbook_url=$custom_cookbook;
	else
		if [ \"$REGION_NAME\" == \"us-east-1\" ]; then
			s3_prefix="s3"
		else
			s3_prefix="s3-$REGION_NAME"
		if
		cookbook_url="https://${s3_prefix}.amazonaws.com/kogencecluster-resources-$REGION_NAME/cookbooks/$kogenceclustercookbookversion.tgz";
	fi

	export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/aws/bin;
	export kogencecluster_version=$kogenceclusterversion;
	export cookbook_version=$kogenceclustercookbookversion;
	export chef_version=$kogenceclusterchefversion;
	export ridley_version=$kogenceclusterridleyversion;
	export berkshelf_version=$kogenceclusterberkshelfversion;
	if [ -f /opt/kogencecluster/.bootstrapped ]; then
		installed_version=$(cat /opt/kogencecluster/.bootstrapped)
		if [ \"$kogencecluster_version\" != \"$installed_version\" ]; then
			bootstrap_instance;
		fi
	else
		bootstrap_instance;
	fi
	mkdir /tmp/cookbooks;
	cd /tmp/cookbooks;
	curl -v -L -o /etc/chef/kogencecluster-cookbook.tgz -z \"$(cat /etc/chef/kogencecluster-cookbook.tgz.date)\" $cookbook_url;
	tar -xzf /etc/chef/kogencecluster-cookbook.tgz;
	cd /tmp
	# Call CloudFormation
	kogence-init ${proxy_args} -s $STACK_NAME -v -c default -r MasterServer --region $REGION_NAME || error_exit 'Failed to run kogence-init. If --norollback was specified, check /var/log/kogence-init.log and /var/log/cloud-init-output.log.';
	kogence-signal ${proxy_args} --exit-code=0 --reason=\"MasterServer setup complete\" --stack=$STACK_NAME --resource=MasterServer --region=$REGION_NAME

	# End of file
}

main () {

	if [ ! -f /tmp/dna.json ]; then
		echo "Create dna.json, client.rb, extra.json."
		echo "\"kogencecluster\" : {" >> /tmp/dna.json;
		echo "\"stack_name\" : \"$STACK_NAME\"" >> /tmp/dna.json;
		echo "\"kogence_preinstall\" : \"$PreInstallScript\"" >> /tmp/dna.json;
		echo "\"kogence_preinstall_args\" : \"$PreInstallArgs\"" >> /tmp/dna.json;
		echo "\"kogence_postinstall\" : \"$PostInstallScript\"" >> /tmp/dna.json;
		echo "\"kogence_postinstall_args\" : \"$PostInstallArgs\"" >> /tmp/dna.json;
		echo "\"kogence_region\" : \"$REGION_NAME\"" >> /tmp/dna.json;
		echo "\"kogence_scheduler\" : \"$Scheduler\"" >> /tmp/dna.json;
		echo "\"kogence_encrypted_ephemeral\" : \"$EncryptedEphemeral\"" >> /tmp/dna.json;
		echo "\"kogence_ephemeral_dir\" : \"$EphemeralDir\"" >> /tmp/dna.json;
		echo "\"kogence_shared_dir\" : \"$SharedDir\"" >> /tmp/dna.json;
		echo "\"kogence_proxy\" : \"$ProxyServer\"" >> /tmp/dna.json;
		echo "\"kogence_node_type\" : \"MasterServer\"" >> /tmp/dna.json;
		echo "\"kogence_cluster_user\" : \"$OSUser\"" >> /tmp/dna.json;
		echo "\"kogence_ddb_table\" : \"$DynamoDBTable\"" >> /tmp/dna.json;
		echo "\"kogence_sqs_queue\" : \"$QueueName\"" >> /tmp/dna.json;
		echo "}," >> /tmp/dna.json;
		echo "\"run_list\" : {" >> /tmp/dna.json;
		if [$CustomChefRunList!="NONE"]; then
			echo $CustomChefRunList >> /tmp/dna.json;
		else
			echo "recipe[kogencecluster::"$Scheduler"_config]" >> /tmp/dna.json;
		fi
		echo "}" >> /tmp/dna.json;
		chmod 644 /tmp/dna.json;
		chown root:root /tmp/dna.json;
	fi
	if [ ! -f  /etc/chef/client.rb ]; then
		echo "cookbook_path ['/etc/chef/cookbooks']" >> /etc/chef/client.rb;
		chmod 644 /etc/chef/client.rb;
		chown root:root /etc/chef/client.rb;
	fi
	if [ ! -f  /tmp/extra.json ]; then
		echo "ExtraJson" >> /tmp/extra.json;
		chmod 644 /tmp/extra.json;
		chown root:root /tmp/extra.json;
	fi

	if [ $# -ne 3 ]; then
		echo "Usages STACK_NAME REGION_NAME PORXY_SERVER";
		setting_config
		exit 0;
	else
		STACK_NAME=$1;
		REGION_NAME=$2
		PORXY_SERVER=$3

		setting_config
	fi
}

# $1: stackname, $2: region, $3 : ProxyServer, 
main $@;