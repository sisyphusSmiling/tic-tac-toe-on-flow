import "FungibleToken"
import "FlowToken"
import "TicTacToe"

transaction {
    prepare(signer: AuthAccount) {
        if signer.type(at: TicTacToe.HandleStoragePath) == nil {
            signer.save(<-TicTacToe.createHandle(name: ""), to: TicTacToe.HandleStoragePath)
        }
        signer.unlink(TicTacToe.PlayerReceiverPublicPath)
        signer.unlink(TicTacToe.ChannelReceiverPublicPath)

        signer.link<&{TicTacToe.PlayerReceiver}>(
            TicTacToe.PlayerReceiverPublicPath,
            target: TicTacToe.HandleStoragePath
        )
        signer.link<&{TicTacToe.ChannelReceiver}>(
            TicTacToe.ChannelReceiverPublicPath,
            target: TicTacToe.HandleStoragePath
        )
    }
}