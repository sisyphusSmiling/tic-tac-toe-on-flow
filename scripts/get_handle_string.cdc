import "TicTacToe"

/// Returns the concatenated String of Handle.name + Handle.id
///
pub fun main(address: Address): String? {
    return getAuthAccount(address).borrow<&TicTacToe.Handle>(from: TicTacToe.HandleStoragePath)
        ?.toString()
        ?? nil
}