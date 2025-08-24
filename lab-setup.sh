#!/bin/bash

# install multipass if not installed
if ! command -v multipass &> /dev/null; then
    echo "Multipass not found. Installing..."
    sudo snap install multipass
fi

SERVER_NAME="landscape-server" 
CLIENT1_NAME="client-jammy"
CLIENT2_NAME="client-noble"
PRO_TOKEN="xxx" # todo: ask a test token from landscape team for talk

# Create landscape-server.yaml
cat <<EOF > landscape-server.yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
  - software-properties-common

runcmd:
  - add-apt-repository -y ppa:landscape/latest-stable
  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y landscape-server-quickstart
EOF

# Create landscape-client.yaml
cat <<EOF > landscape-client.yaml
#cloud-config
package_update: true
package_upgrade: true
packages:
  - software-properties-common

runcmd:
  - add-apt-repository -y ppa:landscape/latest-stable
  - apt-get update
  - sudo pro attach ${PRO_TOKEN} --no-auto-enable
  - apt-get install -y landscape-client
  - echo | openssl s_client -connect ${SERVER_NAME}:443 2>/dev/null | openssl x509 | sudo -u landscape tee /etc/landscape/landscape-server.crt
  - |
      landscape-config \
        --computer-title="\$(hostname)" \
        --account-name standalone \
        --url https://${SERVER_NAME}/message-system \
        --ping-url http://${SERVER_NAME}/ping \
        -k /etc/landscape/landscape-server.crt \
        --silent
EOF

# server configurations
echo "Launching Landscape server (noble)..."
multipass launch noble --name $SERVER_NAME --cpus 4 --memory 6G --disk 450G --cloud-init landscape-server.yaml

SERVER_IP=$(multipass info $SERVER_NAME | grep IPv4 | awk '{print $2}')
echo "$SERVER_IP $SERVER_NAME" | sudo tee -a /etc/hosts
echo "Landscape server at: https://$SERVER_NAME"

# client configurations
while ! multipass exec $SERVER_NAME -- dpkg -l | grep -q "ii  landscape-server"; do
    sleep 10
    echo "Waiting for Landscape server to be ready..."
done

echo "Launching client 1 (jammy)..."
multipass launch jammy --name $CLIENT1_NAME --cpus 2 --memory 2G --cloud-init landscape-client.yaml

echo "Launching client 2 (noble)..."
multipass launch noble --name $CLIENT2_NAME --cpus 2 --memory 2G --cloud-init landscape-client.yaml

echo "Lab setup complete!"
