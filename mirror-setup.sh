#!/bin/bash
set -e

SERVER_NAME="landscape-server" 

echo "Installing landscape-api client..."
sudo snap install landscape-api

# Set up the API keys:
# You must retrieve your API access key 
# and secret key from the Landscape dashboard
# (by clicking on your account name in the upper right corner).
export LANDSCAPE_API_KEY="5ZHIRVJC9TC2BC92LXDI"
export LANDSCAPE_API_SECRET="KSfAW49kj3Cf5FJjFgh0d4xohm8ITlRcdwRxFeSc"
export LANDSCAPE_API_URI="https://${SERVER_NAME}/api/"
# export LANDSCAPE_API_SSL_CA_FILE="/etc/landscape/landscape-server.crt"
# landscape-api snap only has access to home, so adding cert to system store
sudo cp /etc/landscape/landscape-server.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates 

echo "Setting up mirror key..."
# Install rng-tools
sudo apt-get update
sudo apt-get install -y rng-tools jq
sudo rngd -r /dev/urandom

# Generate GPG key
cat > gpg-template.txt <<'EOF'
%no-protection
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: Mirror Key
Name-Email: mirror@example.com
Expire-Date: 0
%commit
EOF

gpg --batch --gen-key gpg-template.txt
KEY_ID=$(gpg --list-keys --with-colons "Mirror Key" | awk -F: '/^pub/{print $5}')
gpg -a --export-secret-keys "$KEY_ID" > mirror-key.asc
echo "GPG key generated and exported: $KEY_ID"

# Import the GPG key into Landscape
landscape-api import-gpg-key mirror-key mirror-key.asc

echo "Creating the mirror..."

# Create the distribution 
landscape-api create-distribution ubuntu

# Create the series with only the 'restricted' component and 'updates' pocket for testing
landscape-api create-series jammy ubuntu \
  --pockets backports \
  --components main \
  --architectures amd64 \
  --gpg-key mirror-key \
  --mirror-uri http://archive.ubuntu.com/ubuntu/ \
  --mirror-series jammy

# Start the mirroring process for the 'updates' pocket
landscape-api sync-mirror-pocket backports jammy ubuntu

echo "Waiting for the mirror sync to complete..."
while true; do
  progress=$(landscape-api get-activities --query type:SyncPocketRequest --limit 1 --json | jq -r '.[0].progress')
  echo "Progress: $progress%"
  [ "$progress" -eq 100 ] && echo "Sync complete!" && break
  sleep 10
done