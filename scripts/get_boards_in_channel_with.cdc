import "TicTacToe"

pub fun main(handleAddress: Address, otherParticipant: Address): [UInt64]? {
    return getAccount(handleAddress).getCapability<&{TicTacToe.ChannelReceiver}>(
        TicTacToe.HandlePublicPath
    ).borrow()
    ?.getBoardsInChannelWith(otherHandleAddress: otherParticipant)
    ?? nil
}