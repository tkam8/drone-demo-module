#!/bin/bash

#Utils
sudo apt-get install unzip

#Download Consul
curl --silent --remote-name https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip

#Install Consul
unzip consul_${CONSUL_VERSION}_linux_amd64.zip
sudo chown root:root consul
sudo mv consul /usr/local/bin/
consul -autocomplete-install
complete -C /usr/local/bin/consul consul

#Create Consul User
sudo useradd --system --home /etc/consul.d --shell /bin/false consul
sudo mkdir --parents /opt/consul
sudo chown --recursive consul:consul /opt/consul

#Create Systemd Config
sudo cat << EOF > /etc/systemd/system/consul.service
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/consul.d/consul.hcl

[Service]
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/
ExecReload=/usr/local/bin/consul reload
KillMode=process
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

#Create config dir
sudo mkdir --parents /etc/consul.d
sudo touch /etc/consul.d/consul.hcl
sudo chown --recursive consul:consul /etc/consul.d
sudo chmod 640 /etc/consul.d/consul.hcl

cat << EOF > /etc/consul.d/consul.hcl
datacenter = "dc1"
data_dir = "/opt/consul"

ui = true
EOF

cat << EOF > /etc/consul.d/server.hcl
server = true
bootstrap_expect = 1

client_addr = "0.0.0.0"
retry_join = ["provider=gce project_name=${PROJECT_NAME} tag_value=consul credentials_file=/tmp/consuler_creds.json"]
EOF

#Enable the service
sudo systemctl enable consul
sudo service consul start
sudo service consul status

#Install Vault
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install vault

#Log in to Vault
vault_address=${VAULT_ADDR}
svc_acct=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email" -H "Metadata-Flavor: Google")

export VAULT_ADDR=$vault_address
export VAULT_SKIP_VERIFY=true

vault login -method=gcp role="${VAULT_ROLE_DEV}" project="${PROJECT_NAME}" service_account="$svc_acct"

#Get creds
vault read -field=private_key_data ${VAULT_RULESET_PATH} | base64 -d > /tmp/consuler_creds.json