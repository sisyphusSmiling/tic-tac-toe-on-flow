import "TicTacToe"

pub fun main(address: Address): String? {
    return getAuthAccount(address).borrow<&TicTacToe.Handle>(from: TicTacToe.HandleStoragePath)
        ?.toString()
        ?? nil
}