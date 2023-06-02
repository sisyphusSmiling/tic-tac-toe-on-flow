import "FungibleToken"
import "FlowToken"
import "TicTacToe"

transaction(withPlayer: Address) {
    
    prepare(signer: AuthAccount) {
        let handle = signer.borrow<&TicTacToe.Handle>(from: TicTacToe.HandleStoragePath)
            ?? panic("Could not retrieve Handle from signer's Storage")
        let channelParticipantRef = handle.borrowChannelParticpantByAddress(withPlayer)
            ?? panic("No channel configured with player ".concat(withPlayer.toString()))
        channelParticipantRef.startNewBoard()
    }
}