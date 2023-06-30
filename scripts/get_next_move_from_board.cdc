import "TicTacToe"

/// Queries the next move from the Board of given ID at the specified Channel Address
///
/// @return true - X's turn | false - O's turn | nil - tie or game over
///
pub fun main(channelAddress: Address, boardID: UInt64): Bool? {
    return getAuthAccount(channelAddress).borrow<&TicTacToe.Board>(
        from: StoragePath(
            identifier: TicTacToe.boardPathPrefix.concat(boardID.toString())
        )!
    )?.getNextMove()
    ?? panic("No Board with given ID found at ".concat(channelAddress.toString()))
}