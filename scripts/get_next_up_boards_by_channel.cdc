import "TicTacToe"

/// Returns a dictionary of Addresses to a list of board IDs that are awaiting the specified Handle's move where the
/// indexing Address is that of the Handle's opponent
/// Given the number of mappings involved, this is not a very scalable query, but could be parsed out into distinct
/// scripts if necessary.
///
pub fun main(handleAddress: Address): {Address: [UInt64]} {

    let statuses: {Address: [UInt64]} = {}

    let handle = getAuthAccount(handleAddress).borrow<&TicTacToe.Handle>(from: TicTacToe.HandleStoragePath) ?? panic("No handle found")

    let addressToIDs: {Address: UInt64} = handle.getAddressesToIDs()
    let channelsToBoards: {UInt64: [UInt64]} = handle.getChannelToBoardIDs()
    let xCaps: {UInt64: Capability<&{TicTacToe.XPlayer}>} = handle.getXPlayerCaps()
    let oCaps: {UInt64: Capability<&{TicTacToe.OPlayer}>}  = handle.getOPlayerCaps()

    for address in addressToIDs.keys {
        let channelID: UInt64 = addressToIDs[address]!
        let boardIDs: [UInt64] = channelsToBoards[channelID]!
        let nextUp: [UInt64] = []

        for boardID in boardIDs {
            if let x = xCaps[boardID] {
                if x.borrow()!.getNextMove() == true {
                    nextUp.append(boardID)
                }
            }
            if let o = oCaps[boardID] {
                if o.borrow()!.getNextMove() == false {
                    nextUp.append(boardID)
                }
            }
        }
        statuses.insert(key: address, nextUp)
    }

    return statuses
}