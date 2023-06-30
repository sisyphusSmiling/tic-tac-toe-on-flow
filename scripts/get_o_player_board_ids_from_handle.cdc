import "TicTacToe"

pub fun main(handleAddress: Address): [UInt64] {

    let handle = getAuthAccount(handleAddress).borrow<&TicTacToe.Handle>(from: TicTacToe.HandleStoragePath) ?? panic("No handle found")

    return handle.getOPlayerCaps().keys
}