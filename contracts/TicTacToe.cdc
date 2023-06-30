import "FungibleToken"
import "FlowToken"

/// TicTacToe
/// Author: Giovanni Sanchez - @sisyphusSmiling
///
/// As it's named, this contract defines onchain TicTacToe.
///
/// The purpose here is to explore notions of neutral ground in adversarial turn-based games in a manner that provides 
/// both fairness gurarantees between players as well as contract utility permanance. These two are often at odds with
/// onchain games on Flow. Optimizing for fairness, a dev might store game resources in the contract account requiring
/// storage funding while optimizing. Optimizing for maintanence costs, a dev might offload game resources to one of 
/// the players, compromising fairness guarntees.AccountKey
///
/// In this contract, AuthAccount Capabilities are utilized to introduce a third option - "channel" accounts. When two
/// players want to play with each other, they open up a channel account in which all game resources are stored. The
/// Channel encapsulates an AuthAccount Capability, defining access rules on the underlying account storage and 
/// expopsing a limited set of write access to each participant of the channel.AccountKey
///
/// The result is a player-funded, trustlessly peer-to-peer gaming solution defined in a contract that can exist as an
/// immortal public good.
///
/* TODO:
    - [ ] Enable board id to channel attribution - need to know which board is for which channel
    - [ ] Problem: Given a Handle, how do I know which boards are currently inPlay and which are currently waiting for my turn?
          This can also be solved by a script if necessary
        - [ ] Look up currently inPlay boards from Handle
        - [ ] Of those inPlay, which are currently waiting for my turn?
    - [ ] Enable withdrawal of funds from Channel account
        - [ ] Track deposits to the Channel by player
    - [ ] Clean up storage in Channel account
        - [ ] Board deletion patterns - multi-auth? What pre-conditions must be met?
    - [ ] TODO - Decide on whether to allow public creation of Boards | Alt is close Board creation to Channel only
        - [ ] PlayerReceiver is public which creates a spam vector with free & public board creation
 */
access(all) contract TicTacToe {

    access(all) var minimumFundingAmount: UFix64

    /* Common Paths */
    //
    access(all) let boardPathPrefix: String
    access(all) let xPlayerPathPrefix: String
    access(all) let oPlayerPathPrefix: String
    access(all) let AdminStoragePath: StoragePath
    access(all) let ChannelStoragePath: StoragePath
    access(all) let ChannelAccountPath: PrivatePath
    access(all) let ChannelParticipantsPrivatePath: PrivatePath
    access(all) let ChannelSpectatorPublicPath: PublicPath
    access(all) let HandleStoragePath: StoragePath
    access(all) let HandlePublicPath: PublicPath
    access(all) let HandlePrivatePath: PrivatePath

    /* Events */
    //
    access(all) event MinimumFundingAmountUpdated(newAmount: UFix64)
    access(all) event ChannelCreated(id: UInt64, address: Address, players: [Address])
    access(all) event ChannelFunded(id: UInt64, address: Address, amount: UFix64)
    access(all) event PlayerLeftChannel(channelID: UInt64, playerID: UInt64, playerAddress: Address)
    access(all) event HandleCreated(id: UInt64, name: String)
    access(all) event HandleNameUpdated(id: UInt64, oldName: String, newName: String)
    access(all) event BoardAddedToChannel(boardID: UInt64, channelID: UInt64, xPlayerAddress: Address, oPlayerAddress: Address)
    access(all) event MoveSubmitted(move: Bool, boardID: UInt64, boardState: [[Bool?]])
    access(all) event GameOver(winner: Bool?, boardID: UInt64)
    // Two-stage deletion - pending: deletion awaiting approval | !pending: deletion complete
    access(all) event BoardDeletion(boardID: UInt64, channelID: UInt64, pending: Bool)

    // ------------------------------
    // Board & Players 
    // ------------------------------
    //
    /// Interface representing player submitting X
    ///
    access(all) resource interface XPlayer {
        access(all) fun getID(): UInt64
        access(all) fun markX(row: Int, column: Int)
    }

    /// Interface representing player submitting O
    ///
    access(all) resource interface OPlayer {
        access(all) fun getID(): UInt64
        access(all) fun markO(row: Int, column: Int)
    }
    
    /// Resource representing board state and acted on by both players
    access(all) resource Board : XPlayer, OPlayer {
        // X: true | O: false | empty: nil
        access(all) let id: UInt64
        access(self) let board: [[Bool?]]
        access(self) var nextMove: Bool?
        access(self) var winner: Bool?
        access(self) var moveCounter: Int
        access(self) var inPlay: Bool

        init() {
            self.id = self.uuid
            self.board = [
                [nil, nil, nil],
                [nil, nil, nil],
                [nil, nil, nil]
            ]
            self.nextMove = true
            self.winner = nil
            self.moveCounter = 0
            self.inPlay = true
        }

        /// Getter for ID
        ///
        access(all) fun getID(): UInt64 {
            return self.id
        }

        /// Marks true (AKA X) at the specified cell
        ///
        access(all) fun markX(row: Int, column: Int) {
            self.submitMove(move: true, row: row, column: column)
        }
        
        /// Marks false (AKA O) at the specified cell
        ///
        access(all) fun markO(row: Int, column: Int) {
            self.submitMove(move: false, row: row, column: column)
        }
        
        /// Submits the given move at the specified cell
        ///
        access(self) fun submitMove(move: Bool, row: Int, column: Int) {
            pre {
                self.inPlay: "Board is no longer in play"
                self.nextMove == move: "This move is not allowed for this round"
                self.board[row][column] == nil: "The cell has already been marked"
            }
            // Update move trackers
            self.moveCounter = self.moveCounter + 1
            self.nextMove = !move

            self.board[row][column] = move

            emit MoveSubmitted(move: move, boardID: self.getID(), boardState: self.getBoard())
            
            if let winner = TicTacToe.getWinner(self.board) {
                self.winner = winner
            }
            if self.moveCounter == 9 || self.winner != nil {
                self.inPlay = false
            }
            if !self.inPlay {
                emit GameOver(winner: self.getWinner(), boardID: self.getID())
            }
        }

        /// Getter to check if board is in play
        ///
        access(all) fun isInPlay(): Bool {
            return self.inPlay
        }

        /// Getter for winner - true == X | false == O | nil otherwise
        ///
        access(all) fun getWinner(): Bool? {
            return self.winner
        }

        /// Getter for board state
        ///
        access(all) fun getBoard(): [[Bool?]] {
            return self.board
        }

        /// Getter for next move
        ///
        access(all) fun getNextMove(): Bool? {
            return self.nextMove
        }
    }

    // ------------------------------
    // Channel
    // ------------------------------
    //
    access(all) resource interface ChannelSpectator {
        access(all) fun getID(): UInt64
        access(all) fun getChannelParticipantAddresses(): [Address?]
        access(all) fun getChannelParticipantPlayerIDs(): [UInt64]
        access(all) fun getStoredBoardIDs(): [UInt64]
    }
    /// Enables particpants to start new games with each other
    ///
    access(all) resource interface ChannelParticipant {
        access(all) fun getID(): UInt64
        access(all) fun getChannelParticipantAddresses(): [Address?]
        access(all) fun getChannelParticipantPlayerIDs(): [UInt64]
        access(all) fun startNewBoard()
        access(all) fun fundChannel(vault: @FungibleToken.Vault)
        access(all) fun deleteBoard(boardID: UInt64, handleID: &{HandleID})
        access(contract) fun removePlayerCallback(_ id: UInt64)
    }

    /// Channels can be thought of as a Web3 notion of a "game server" where players engage in play on neutral grounds,
    /// storing Board resources and allocating each player's Capability on the Board (pseudo) randomly.
    ///
    access(all) resource Channel : ChannelParticipant {

        /// Capability to the underlying account storing all Boards for this Channel
        access(self) let accountCap: Capability<&AuthAccount>
        /// Mapping of Player IDs to their Capabilities so board Capabilities can be transmitted on creation
        access(self) let playerCaps: {UInt64: Capability<&{PlayerReceiver}>?}
        /// Array containing IDs of stored boards
        access(self) let storedBoards: [UInt64]
        /// Mapping of Board IDs pending deletion approval with values of initiating ChannelParticipant ID
        access(self) let pendingDeletions: {UInt64: UInt64}

        init(accountCap: Capability<&AuthAccount>, player1: Capability<&{PlayerReceiver}>, player2: Capability<&{PlayerReceiver}>) {
            pre {
                player1.check(): "Invalid Player 1 Capability"
                player2.check(): "Invalid Player 2 Capability"
            }
            self.accountCap = accountCap
            self.playerCaps = {
                player1.borrow()!.getID(): player1,
                player2.borrow()!.getID(): player2
            }
            self.storedBoards = []
            self.pendingDeletions = {}
        }

        /// Getter for Channel ID
        ///
        access(all) fun getID(): UInt64 {
            return self.uuid
        }

        /// Returns the Addresses of both players. Values can be nil if player has left the Channel
        ///
        access(all) fun getChannelParticipantAddresses(): [Address?] {
            return [self.playerCaps.values[0]?.address, self.playerCaps.values[1]?.address]
        }

        /// Returns the IDs of both PlayerParticipants
        ///
        access(all) fun getChannelParticipantPlayerIDs(): [UInt64] {
            return self.playerCaps.keys
        }
        
        /// Returns the IDs of all stored Boards
        ///
        access(all) fun getStoredBoardIDs(): [UInt64] {
            return self.storedBoards
        }

        /// Creates a new Board, saving in the Channel account, linking and issuing player Capabilities, assigning
        /// X and O (pseudo) randomly
        ///
        access(all) fun startNewBoard() {
            pre {
                self.playerCaps[self.playerCaps.keys[0]] != nil && self.playerCaps[self.playerCaps.keys[1]] != nil:
                    "One of the players has left this channel"
            }
            let account = self.accountCap.borrow() ?? panic("Problem with AuthAccount Capability")
            let board <- create Board()
            let boardID = board.getID()
            self.storedBoards.append(boardID)

            let boardStoragePath = StoragePath(identifier: TicTacToe.boardPathPrefix.concat(boardID.toString()))!
            let xPrivatePath = PrivatePath(identifier: TicTacToe.xPlayerPathPrefix.concat(boardID.toString()))!
            let oPrivatePath = PrivatePath(identifier: TicTacToe.oPlayerPathPrefix.concat(boardID.toString()))!

            account.save(<-board, to: boardStoragePath)
            account.link<&{XPlayer}>(xPrivatePath, target: boardStoragePath)
            account.link<&{OPlayer}>(oPrivatePath, target: boardStoragePath)

            let xCap = account.getCapability<&{XPlayer}>(xPrivatePath)
            let oCap = account.getCapability<&{OPlayer}>(oPrivatePath)

            let coinFlip = unsafeRandom() % 2
            let xPlayerID = self.playerCaps.keys[coinFlip]
            let oPlayerID = self.playerCaps.keys[(coinFlip + 1) % 2]

            let xPlayerCap = self.playerCaps[xPlayerID]!
            let oPlayerCap = self.playerCaps[oPlayerID]!

            xPlayerCap!.borrow()?.addXPlayerCapability(xCap)
                ?? panic("Problem with PlayerReceiver Capability for player with Address: ".concat(xPlayerCap!.address.toString()))
            oPlayerCap!.borrow()?.addOPlayerCapability(oCap)
                ?? panic("Problem with PlayerReceiver Capability for player with Address: ".concat(oPlayerCap!.address.toString()))

            emit BoardAddedToChannel(boardID: boardID, channelID: self.getID(), xPlayerAddress: xPlayerCap!.address, oPlayerAddress: oPlayerCap!.address)
        }

        /// Two-stage deletion process where the first participant can initiate a deletion and the second participant
        /// must approve deletion for it to take effect. This destroys the Board and unlinks related Capabilities.
        ///
        access(all) fun deleteBoard(boardID: UInt64, handleID: &{HandleID}) {
            pre {
                self.getChannelParticipantAddresses().contains(handleID.owner!.address) && self.getChannelParticipantPlayerIDs().contains(handleID.getID()):
                    "Caller is not a member of this Channel"
                self.pendingDeletions[boardID] == nil || self.pendingDeletions[boardID] != handleID.getID():
                    "Board is already pending deletion"
                self.storedBoards.contains(boardID):
                    "Board with given ID does not exist")
            }
            if self.pendingDeletions[boardID] == nil {
                self.pendingDeletions[boardID] = handleID.getID()
                emit BoardDeletion(boardID: boardID, channelID: self.getID(), pending: true)
            } else {
                let account = self.accountCap.borrow() ?? panic("Problem with AuthAccount Capability")

                let boardStoragePath = StoragePath(identifier: TicTacToe.boardPathPrefix.concat(boardID.toString()))!
                let xPrivatePath = PrivatePath(identifier: TicTacToe.xPlayerPathPrefix.concat(boardID.toString()))!
                let oPrivatePath = PrivatePath(identifier: TicTacToe.oPlayerPathPrefix.concat(boardID.toString()))!
                
                account.unlink(xPrivatePath)
                account.unlink(oPrivatePath)

                let board <- account.load<@Board>(from: boardStoragePath)
                destroy board
                
                self.storedBoards.remove(at: self.storedBoards.firstIndex(of: boardID)!)
                self.pendingDeletions.remove(key: boardID)
                
                emit BoardDeletion(boardID: boardID, channelID: self.getID(), pending: false)
            }
        }

        /// Allows participants to fund this Channel's account, used for storage fees
        ///
        access(all) fun fundChannel(vault: @FungibleToken.Vault) {
            emit ChannelFunded(id: self.getID(), address: self.owner!.address, amount: vault.balance)
            let accountRef: &AuthAccount = self.accountCap.borrow()!
            accountRef.borrow<&FungibleToken.Vault>(from: /storage/flowTokenVault)!.deposit(
                from: <-vault
            )
        }

        /// Enables a player to leave the channel, replacing their PlayerReceiver Capability with nil
        ///
        access(contract) fun removePlayerCallback(_ id: UInt64) {
            pre {
                self.playerCaps[id] != nil:
                    "Player with ID: ".concat(id.toString()).concat(" is not a member of this Channel")
            }
            self.playerCaps[id] = nil
        }
    }

    // ------------------------------
    // Handle
    // ------------------------------
    //
    /// Enables one to receive XPlayer and OPlayer Capabilities
    ///
    access(all) resource interface PlayerReceiver {
        access(all) fun getID(): UInt64
        access(all) fun getName(): String
        access(contract) fun addXPlayerCapability(_ cap: Capability<&{XPlayer}>)
        access(contract) fun addOPlayerCapability(_ cap: Capability<&{OPlayer}>)
        access(all) fun toString(): String
    }

    /// Enables one to receive Channel Capabilities
    ///
    access(all) resource interface ChannelReceiver {
        access(all) fun getID(): UInt64
        access(all) fun getName(): String
        access(contract) fun addChannelParticipantCapability(_ cap: Capability<&{ChannelParticipant}>)
        access(all) fun toString(): String
    }

    access(all) resource interface HandleID {
        access(all) fun getID(): UInt64
        access(all) fun getName(): String
        access(all) fun toString(): String
    }

    /// API through which a user interfaces with the game, managing both Channel as well as the XPlayer and OPlayer
    /// Capabilities
    ///
    // TODO:
    // - [ ] How do I know which boards are in play with a given player (IOW in a given channel)?
    // - [ ] How do I know which boards are awaiting my turn?
    access(all) resource Handle : PlayerReceiver, ChannelReceiver {
        access(self) var name: String
        // TODO: Consider namespacing on channeAddress.boardID
        access(self) let xPlayerCaps: {UInt64: Capability<&{XPlayer}>}
        access(self) let oPlayerCaps: {UInt64: Capability<&{OPlayer}>}
        
        access(self) let channelParticipantCaps: {UInt64: Capability<&{ChannelParticipant}>}
        /// Mapping of Address to Channel.id where Address is that of the other player in the Channel
        access(self) let channelAddressesToIDs: {Address: UInt64}

        init(name: String) {
            pre {
                name.length <= 32: "Name must be less than 32 characters"
            }
            self.name = name
            self.xPlayerCaps = {}
            self.oPlayerCaps = {}
            self.channelParticipantCaps = {}
            self.channelAddressesToIDs = {}
        }

        access(all) fun getID(): UInt64 {
            return self.uuid
        }

        access(all) fun getName(): String {
            return self.name
        }

        access(all) fun setName(_ new: String) {
            pre {
                new.length <= 32: "Name must be less than 32 characters"
            }
            let old = self.name
            self.name = new
            emit HandleNameUpdated(id: self.getID(), oldName: old, newName: new)
        }

        access(contract) fun addXPlayerCapability(_ cap: Capability<&{XPlayer}>) {
            pre {
                cap.check(): "Invalid Capability"
                self.xPlayerCaps[cap.borrow()!.getID()] == nil: "Already have Capability for this Board"
                self.oPlayerCaps[cap.borrow()!.getID()] == nil: "Already playing X for this Board"
            }
            self.xPlayerCaps.insert(key: cap.borrow()!.getID(), cap)
        }

        access(contract) fun addOPlayerCapability(_ cap: Capability<&{OPlayer}>) {
            pre {
                cap.check(): "Invalid Capability"
                self.oPlayerCaps[cap.borrow()!.getID()] == nil: "Already have Capability for this Board"
                self.xPlayerCaps[cap.borrow()!.getID()] == nil: "Already playing O for this Board"
            }
            self.oPlayerCaps.insert(key: cap.borrow()!.getID(), cap)
        }

        access(all) fun borrowXPlayer(id: UInt64): &{XPlayer}? {
            return self.xPlayerCaps[id]?.borrow() ?? nil
        }

        access(all) fun borrowOPlayer(id: UInt64): &{OPlayer}? {
            return self.oPlayerCaps[id]?.borrow() ?? nil
        }

        access(all) fun removeXPlayerCapability(id: UInt64): Bool {
            return self.xPlayerCaps.remove(key: id) != nil
        }

        access(all) fun removeOPlayerCapability(id: UInt64): Bool {
            return self.oPlayerCaps.remove(key: id) != nil
        }

        access(contract) fun addChannelParticipantCapability(_ cap: Capability<&{ChannelParticipant}>) {
            pre {
                cap.check(): "Invalid Capability"
                self.channelParticipantCaps[cap.borrow()!.getID()] == nil: "Already have Capability for this Channel"
                cap.borrow()!.getChannelParticipantAddresses().contains(self.owner!.address):
                    "Cannot add a ChannelParticipant Capability for a Channel this account is not a participant of"
            }
            let channelRef = cap.borrow()!
            self.channelParticipantCaps.insert(key: channelRef.getID(), cap)
            
            let participants = channelRef.getChannelParticipantAddresses()
            let other = participants[0] != self.owner!.address ? participants[0]! : participants[1]!
            self.channelAddressesToIDs.insert(key: other, channelRef.getID())
        }

        access(all) fun borrowChannelParticpantByAddress(_ address: Address): &{ChannelParticipant}? {
            if let channelID = self.channelAddressesToIDs[address] {
                if let channelCap = self.channelParticipantCaps[channelID] {
                    return channelCap.borrow() ?? panic("Problem with ChannelParticipant Capability")
                }
            }
            return nil
        }

        access(all) fun leaveChannel(id: UInt64): Bool {
            if !self.channelParticipantCaps.containsKey(id) {
                return false
            }
            if let channelRef = self.channelParticipantCaps.remove(key: id)!.borrow() {
                channelRef.removePlayerCallback(self.getID())
                emit PlayerLeftChannel(channelID: id, playerID: self.getID(), playerAddress: self.owner!.address)
            }
            return true
        }

        access(all) fun getChannelAddresses(): [Address] {
            return self.channelAddressesToIDs.keys
        }

        access(all) fun toString(): String {
            return self.name.concat("#").concat(self.getID().toString())
        }
    }

    /// Creates a new account, saving and linking a new Channel which encapsulates the given Capabilities. Two 
    /// Capabilities on the Channel are given to the provided ChannelReceivers. The fundingVault is required to fund
    /// the new account's creation.
    ///
    access(all) fun createChannel(
        playerReceiver1: Capability<&{PlayerReceiver}>,
        playerReceiver2: Capability<&{PlayerReceiver}>,
        channelReceiver1: &{ChannelReceiver},
        channelReceiver2: &{ChannelReceiver},
        fundingVault: @FungibleToken.Vault
    )  {
        pre {
            fundingVault.balance >= self.minimumFundingAmount: "Minimum funding amount not met"
            playerReceiver1.check(): "Invalid playerReceiver1 Capability"
            playerReceiver2.check(): "Invalid playerReceiver2 Capability"
            playerReceiver1.borrow()!.getID() != playerReceiver2.borrow()!.getID() &&
            channelReceiver1.getID() != channelReceiver2.getID():
                "Can't play against yourself"
            playerReceiver1.borrow()!.getID() == channelReceiver1.getID():
                "playerReceiver1 and channelReceiver1 must resolve to same Handle!"
            playerReceiver2.borrow()!.getID() == channelReceiver2.getID():
                "playerReceiver2 and channelReceiver2 must resolve to same Handle!"
        }
        // Take receipt of the funding Vault, noting its balance
        let vaultRef = self.account.borrow<&FungibleToken.Vault>(from: /storage/flowTokenVault)!
        let fundingBalance = fundingVault.balance - self.minimumFundingAmount
        vaultRef.deposit(from: <-fundingVault)

        // Create a new account, depositing any surplus balance
        let neutralAccount = AuthAccount(payer: self.account)
        

        // Link an AuthAccount Capability and create a Channel
        let accountCap = neutralAccount.linkAccount(self.ChannelAccountPath)!
        let channel<-create Channel(
                accountCap: accountCap,
                player1: playerReceiver1,
                player2: playerReceiver2
            )
        emit ChannelCreated(id: channel.getID(), address: neutralAccount.address, players: [playerReceiver1.address, playerReceiver2.address])
        if fundingBalance > 0.0 {
            channel.fundChannel(
                vault: <-vaultRef.withdraw(amount: fundingBalance)
            )
        }
        // Save and link the Channel
        neutralAccount.save(
            <-channel,
            to: self.ChannelStoragePath
        )
        neutralAccount.link<&{ChannelParticipant}>(self.ChannelParticipantsPrivatePath, target: self.ChannelStoragePath)
        
        // Give each player a ChannelParticipant Capability 
        let channelParticipantCap = neutralAccount.getCapability<&{ChannelParticipant}>(self.ChannelParticipantsPrivatePath)
        channelReceiver1.addChannelParticipantCapability(channelParticipantCap)
        channelReceiver2.addChannelParticipantCapability(channelParticipantCap)
    }

    // ------------------------------
    // Admin
    // ------------------------------
    //
    /// Enables update on minimumFundingAmount for new Channel creation
    ///
    pub resource Admin {
        pub fun setMinimumFundingAmount(_ new: UFix64) {
            TicTacToe.minimumFundingAmount = new
            emit MinimumFundingAmountUpdated(newAmount: new)
        }
    }

    // ------------------------------
    // Contract Methods
    // ------------------------------
    //
    /// Allows deploying account to create an Admin resource
    ///
    access(account) fun createAdmin(): @Admin {
        return <- create Admin()
    }

    /// Returns a new Handle resource
    ///
    access(all) fun createHandle(name: String): @Handle {
        let handle <-create Handle(name: name)
        emit HandleCreated(id: handle.getID(), name: name)
        return <- handle
    }

    /* --- Resolution logic --- */
    //
    /// Very naïve and totally not efficient, but it works
    ///
    access(all) fun getWinner(_ board: [[Bool?]]): Bool? {
        if let row = self.checkRows(board) {
            return row
        }
        if let column = self.checkColumns(board) {
            return column
        }
        if let diagonal = self.checkDiagonal(board) {
            return diagonal
        }
        return nil
    }

    /// Checks for winning row, returning the matching Bool or nil if not found
    ///
    access(self) fun checkRows(_ board: [[Bool?]]): Bool? {
        for r in board {
            if r[0] != nil && (r[0] == r[1] && r[1] == r[2]) {
                return r[0]
            }
        }
        return nil
    }

    /// Checks for winning column, returning the matching Bool or nil if not found
    ///
    access(self) fun checkColumns(_ board: [[Bool?]]): Bool? {
        var col = 0
        while col < board.length {
            if board[0][col] != nil && (board[0][col] == board[1][col] && board[1][col] == board[2][col]) {
                return board[0][col]
            }
            col = col + 1
        }
        return nil
    }

    /// Checks for winning diagonal, returning the matching Bool or nil if not found
    ///
    access(self) fun checkDiagonal(_ board: [[Bool?]]): Bool? {
        if board[0][0] != nil && (board[0][0] == board[1][1] && board[1][1] == board[2][2]) ||
           board[0][2] != nil && (board[0][2] == board[1][1] && board[1][1] == board[2][0]) {
            return board[0][0]
        }
        return nil
    }

    init() {
        self.minimumFundingAmount = 1.0

        self.boardPathPrefix = "TicTacToeBoard_"
        self.xPlayerPathPrefix = "TicTacToeXPlayer_"
        self.oPlayerPathPrefix = "TicTacToeOPlayer_"

        self.AdminStoragePath = /storage/TicTacToeAdmin
        self.HandleStoragePath = /storage/TicTacToeHandle
        self.HandlePublicPath = /public/TicTacToeHandle
        self.HandlePrivatePath = /private/TicTacToeHandleID
        self.ChannelStoragePath = /storage/TicTacToeChannel
        self.ChannelAccountPath = /private/ChannelAccountCapability
        self.ChannelParticipantsPrivatePath = /private/TicTacToeChannelParticipant
        self.ChannelSpectatorPublicPath = /public/TicTacToeChannelSpectator
    }
}