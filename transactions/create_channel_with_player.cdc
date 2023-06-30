#allowAccountLinking

import "FungibleToken"
import "FlowToken"
import "TicTacToe"

transaction(withPlayer: Address, fundingAmount: UFix64) {
    prepare(signer: AuthAccount) {
        // Get PlayerReceiver Capabilities
        let playerReceiver1Cap = signer.getCapability<&{TicTacToe.PlayerReceiver}>(TicTacToe.HandlePublicPath)
        let playerReceiver2Cap = getAccount(withPlayer).getCapability<&{TicTacToe.PlayerReceiver}>(TicTacToe.HandlePublicPath)

        assert(playerReceiver1Cap.check(), message: "Problem with signer's PlayerReceiver Capability")
        assert(playerReceiver2Cap.check(), message: "Problem with target Address PlayerReceiver Capability")

        // Get reference to ChannelReceiver
        let channelReceiver1Ref = signer.borrow<&{TicTacToe.ChannelReceiver}>(from: TicTacToe.HandleStoragePath)
            ?? panic("Signer doesn't have Handle configured in Storage")
        let channelReceiver2Ref = getAccount(withPlayer).getCapability<&{TicTacToe.ChannelReceiver}>(TicTacToe.HandlePublicPath)
            .borrow()
            ?? panic("Problem retrieving ChannelReceiver from target account")
        
        let handleRef = signer.borrow<&TicTacToe.Handle>(from: TicTacToe.HandleStoragePath)!
        if !handleRef.getChannelAddresses().contains(withPlayer) {
            let vaultRef = signer.borrow<&FungibleToken.Vault>(from: /storage/flowTokenVault)
                ?? panic("Proble with signer's FlowToken Vault")
            let fundingVault <- vaultRef.withdraw(amount: fundingAmount)
            TicTacToe.createChannel(
                playerReceiver1: playerReceiver1Cap,
                playerReceiver2: playerReceiver2Cap,
                channelReceiver1: channelReceiver1Ref,
                channelReceiver2: channelReceiver2Ref,
                fundingVault: <-fundingVault
            )
        }
    }
}