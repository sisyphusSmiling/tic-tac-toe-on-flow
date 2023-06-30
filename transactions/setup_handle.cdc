import "FungibleToken"
import "FlowToken"
import "TicTacToe"

transaction(handleName: String) {
    prepare(signer: AuthAccount) {
        if signer.type(at: TicTacToe.HandleStoragePath) == nil {
            signer.save(<-TicTacToe.createHandle(name: handleName), to: TicTacToe.HandleStoragePath)
        }
        signer.unlink(TicTacToe.HandlePublicPath)
        signer.unlink(TicTacToe.HandlePrivatePath)

        signer.link<&{TicTacToe.PlayerReceiver, TicTacToe.ChannelReceiver}>(
            TicTacToe.HandlePublicPath,
            target: TicTacToe.HandleStoragePath
        )

        signer.link<&{TicTacToe.HandleID}>(
            TicTacToe.HandlePrivatePath,
            target: TicTacToe.HandleStoragePath
        )
    }
}