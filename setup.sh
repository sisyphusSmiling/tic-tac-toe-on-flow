#!/bin/bash

# Create player1 account e03daebed8ca0615 with private key 487f8dca35785c4e464dc2231f82d483258565c50bfac411a4f181bd05c9da65
flow accounts create --key "0641dc6fdfb1a7be52996e3d652302540b0313991e5f881ab3758615f67f2f46d387a488bba174b8fe6aa862efc7e5c01d895326284ba92694c8affc36346e1f"

# Create player2 account 045a1763c93006ca with private key 62562ff408346364c6549b557aa19e0891a9d50cd070df39e25a63fe77b9429f
flow accounts create --key "902f4b45ec9fe2a3e95dc87f7242827e061cf6a72c696baf31b095da37bf93b6d7b34906db6846f4d895ce2230e1002962ef84ebae104faac588d6cbab471f12"

# Deploy contracts
flow deploy

# Mint 100 $FLOW to player1 account
flow transactions send ./transactions/transfer_flow.cdc e03daebed8ca0615 100.0

# Mint 100 $FLOW to player2 account
flow transactions send ./transactions/transfer_flow.cdc 045a1763c93006ca 100.0