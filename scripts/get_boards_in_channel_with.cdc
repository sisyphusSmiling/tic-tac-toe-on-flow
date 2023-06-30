import "TicTacToe"

/// Returns the list of boards in the channel between the given handles at both Addresses
///
pub fun main(handleAddress: Address, otherParticipant: Address): [UInt64]? {
    return getAccount(handleAddress).getCapability<&{TicTacToe.ChannelReceiver}>(
        TicTacToe.HandlePublicPath
    ).borrow()
    ?.getBoardsInChannelWith(otherHandleAddress: otherParticipant)
    ?? nil
}