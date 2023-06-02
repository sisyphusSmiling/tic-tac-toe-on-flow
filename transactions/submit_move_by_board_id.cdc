import "TicTacToe"

transaction(boardID: UInt64, row: Int, column: Int) {
    
    prepare(signer: AuthAccount) {
        let handleRef = signer.borrow<&TicTacToe.Handle>(from: TicTacToe.HandleStoragePath)
            ?? panic("No Handle found in signing account")
        if let xPlayer = handleRef.borrowXPlayer(id: boardID) {
            xPlayer.markX(row: row, column: column)
            return
        }
        if let oPlayer = handleRef.borrowOPlayer(id: boardID) {
            oPlayer.markO(row: row, column: column)
            return
        }
        panic("No Board with given ID found")
    }
}