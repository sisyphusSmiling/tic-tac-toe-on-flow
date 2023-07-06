#!/bin/bash

# Create player1 account 01cf0e2f2f715450 with private key 3406feeed3f7b511165f489da8889a58f7a0f63ed5aaec482a6f8792176468a3
flow accounts create --key "b5e5fd581b7d9b3190cc3810b27f7116d69f03f6c53d5a2cfccd62e7921320d4f6cb4222318eb4b680b49cfbea7dcf8178fa928358311687702f4fcd53549043"

# Create player2 account 179b6b1cb6755e31 with private key 6c2a6bc1771282dfcd5d981c85fd88dd1bfa4a782d74f9686eb377c8790f163c
flow accounts create --key "8e730f98c9d6484b6a161ead7c42138fa1572589dcf12fdd382750e77924b3f5039d56ec9513c36674264660905d25201720d88e238b7a2ea33f59f9a309df49"

# Deploy contracts
flow deploy

# Mint 100 $FLOW to player1 account
flow transactions send ./transactions/transfer_flow.cdc 01cf0e2f2f715450 100.0

# Mint 100 $FLOW to player2 account
flow transactions send ./transactions/transfer_flow.cdc 179b6b1cb6755e31 100.0