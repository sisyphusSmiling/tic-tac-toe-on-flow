import "FungibleToken"
import "FlowToken"

transaction(recipient: Address, amount: UFix64) {
    prepare(signer: AuthAccount) {
        let fromVault <- signer.borrow<&FungibleToken.Vault>(from: /storage/flowTokenVault)
            ?.withdraw(amount: amount)
            ?? panic("Could not access signer's FlowToken Vault")
        let receiverRef = getAccount(recipient).getCapability<&{FungibleToken.Receiver}>(
                /public/flowTokenReceiver
            ).borrow()
            ?? panic("Could not access recipients's FlowToken Receiver")
        receiverRef.deposit(from: <-fromVault)
    }
}