#!/bin/bash

HERMES_SOURCE=https://github.com/informalsystems/hermes/releases/download/v1.4.0/hermes-v1.4.0-x86_64-unknown-linux-gnu.tar.gz

# Update and install required packages, set timezone to UTC
sudo apt-get update
sudo apt-get install -yy git build-essential curl jq unzip moreutils net-tools
sudo timedatectl set-timezone UTC

function loadEnv {
  ENV=/home/vagrant/.env
  if test -f $ENV ; then 
      export $(grep "^[^#;]" $ENV | xargs)
      echo "loaded configuration from ENV file: $ENV"
  else
      echo "ENV file not found at $ENV"
      exit 1
  fi
}

function get_terminal_command() {
  local desktop_env
  desktop_env="$(echo $XDG_CURRENT_DESKTOP | tr '[:upper:]' '[:lower:]')"

  case $desktop_env in
    *gnome*)
      echo "gnome-terminal --"
      ;;
    *)
      echo "xterm -e"
      ;;
  esac
}

function setNodeVars() {
  if [ "$CHAIN_ID" == "provider-chain" ]; then
    DAEMON_NAME=$PROVIDER_APP
    DAEMON_HOME=$PROVIDER_HOME
    DAEMON_REPO=$PROVIDER_REPO
    DAEMON_VERSION=$PROVIDER_VERSION
    DAEMON_GO_SOURCE=$PROVIDER_GO_SOURCE
  elif [ "$CHAIN_ID" == "consumer-chain" ]; then
    DAEMON_NAME=$CONSUMER_APP
    DAEMON_HOME=$CONSUMER_HOME
    DAEMON_REPO=$CONSUMER_REPO
    DAEMON_VERSION=$CONSUMER_VERSION
    DAEMON_GO_SOURCE=$CONSUMER_GO_SOURCE
  fi
}

function installGo() {
  wget -4 $DAEMON_GO_SOURCE -O $(basename $DAEMON_GO_SOURCE)
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf $(basename $DAEMON_GO_SOURCE)
  rm $(basename $DAEMON_GO_SOURCE)
  mkdir -p /home/vagrant/go/bin
  export GOROOT=/usr/local/go
  export GOPATH=/home/vagrant/go
  export GO111MODULE=on
  export PATH=$PATH:$GOROOT/bin
}

function installNode() {
  LOCAL_REPO=$DAEMON_NAME-core
  if [ -d $LOCAL_REPO ] ; then
    rm -r $LOCAL_REPO
  fi
  mkdir $LOCAL_REPO
  git clone $DAEMON_REPO $LOCAL_REPO
  cd $LOCAL_REPO
  git checkout $DAEMON_VERSION
  make install
  sudo mv /home/vagrant/go/bin/$DAEMON_NAME /usr/local/bin
  cd ..
  rm -rf $LOCAL_REPO
}

function initNode() {
  NODE_MONIKER="${CHAIN_ID}-validator${NODE_INDEX}"
  $DAEMON_NAME init "$NODE_MONIKER" --chain-id "$CHAIN_ID" --home $DAEMON_HOME
}

function manipulateGenesis() {
  if [ "$CHAIN_ID" == "provider-chain" ]; then
    sed -i 's/stake/icsstake/g' $DAEMON_HOME/config/genesis.json
    jq '.app_state.staking.params.unbonding_time = "1814400s"' $DAEMON_HOME/config/genesis.json | sponge $DAEMON_HOME/config/genesis.json
    jq '.app_state.gov.voting_params.voting_period = "60s"' $DAEMON_HOME/config/genesis.json | sponge $DAEMON_HOME/config/genesis.json
    # jq '.app_state.gov.params.deposit_params.min_deposit[0].amount = "1"' $DAEMON_HOME/config/genesis.json | sponge $DAEMON_HOME/config/genesis.json
  
    GENESIS_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ" --date="@$(($(date +%s) - 60))")
    jq --arg time "$GENESIS_TIME" '.genesis_time = $time' $DAEMON_HOME/config/genesis.json | sponge $DAEMON_HOME/config/genesis.json
  fi
}

function genTx() {
  if [ "$CHAIN_ID" == "provider-chain" ]; then
    $DAEMON_NAME --home $DAEMON_HOME keys add "$NODE_MONIKER" --keyring-backend test
    $DAEMON_NAME --home $DAEMON_HOME add-genesis-account $($DAEMON_NAME keys --home $DAEMON_HOME show "$NODE_MONIKER" -a --keyring-backend test) 1500000000000icsstake --keyring-backend test
    $DAEMON_NAME --home $DAEMON_HOME gentx "$NODE_MONIKER" 1000000000icsstake --chain-id "$CHAIN_ID" --keyring-backend test
  fi
}

function installRelayer() {
  if [ "$CHAIN_ID" == "provider-chain" ] && [ "$NODE_INDEX" == "1" ]; then
    wget $HERMES_SOURCE -O hermes.tar.gz
    mkdir -p /home/vagrant/.hermes/bin
    tar -C /home/vagrant/.hermes/bin/ -vxzf hermes.tar.gz
    rm hermes.tar.gz
    export PATH="/home/vagrant/.hermes/bin:$PATH"
    sudo chmod -R 777 /home/vagrant/.hermes
  fi
}

function updatePermissions() {
  echo "Updating permissions..."
  sudo chmod -R 777 $DAEMON_HOME
}

main() {
  loadEnv
  setNodeVars
  installGo
  installNode
  initNode
  manipulateGenesis
  genTx
  installRelayer
  updatePermissions
}

main && echo "SUCCESS >> node provisioned"