import "TicTacToe"

transaction(newName: String) {
    prepare(signer: AuthAccount) {
        signer.borrow<&TicTacToe.Handle>(from: TicTacToe.HandleStoragePath)
            ?.setName(newName)
            ?? panic("No Handle found in signer's account")
    }
}