#!/usr/bin/env bash
source .env
forge script script/XDaiForeignBridge.s.sol:XDaiForeignBridgeDeployer --fork-url http://127.0.0.1:8545 --broadcast

