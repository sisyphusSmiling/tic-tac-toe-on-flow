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
access(all) contract TicTacToe {

    access(all) var minimumFundingAmount: UFix64

    /* Common Paths */
    //
    access(all) let AdminStoragePath: StoragePath
    access(all) let BoardStoragePath: StoragePath
    access(all) let XPlayerPrivatePath: PrivatePath
    access(all) let OPlayerPrivatePath: PrivatePath
    access(all) let ChannelStoragePath: StoragePath
    access(all) let ChannelAccountPath: PrivatePath
    access(all) let ChannelParticipantsPrivatePath: PrivatePath
    access(all) let HandleStoragePath: StoragePath
    access(all) let PlayerReceiverPublicPath: PublicPath
    access(all) let ChannelReceiverPublicPath: PublicPath
P
    /* Events */
    //
    access(all) event MinimumFundingAmountUpdated(newAmount: UFix64)
    access(all) event ChannelCreated(id: UInt64, address: Address, players: [Address])
    access(all) event ChannelFunded(id: UInt64, address: Address, amount: UFix64)
    access(all) event BoardCreated(id: UInt64)
    access(all) event HandleCreated(id: UInt64, name: String)
    access(all) event HandleNameUpdated(id: UInt64, oldName: String, newName: String)
    access(all) event BoardAddedToChannel(boardID: UInt64, channelID: UInt64, xPlayerAddress: Address, oPlayerAddress: Address)
    access(all) event MoveSubmitted(move: Bool, boardID: UInt64, boardState: [[Bool?]])
    access(all) event GameOver(winner: Bool?, boardID: UInt64)

    /* Board & Players */
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

    /* Handle interfaces */
    //
    /// Enables one to receive XPlayer and OPlayer Capabilities
    ///
    access(all) resource interface PlayerReceiver {
        access(all) fun getID(): UInt64
        access(all) fun getName(): String
        access(all) fun addXPlayerCapability(_ cap: Capability<&{XPlayer}>)
        access(all) fun addOPlayerCapability(_ cap: Capability<&{OPlayer}>)
        access(all) fun toString(): String
    }

    /// Enables one to receive Channel Capabilities
    ///
    access(all) resource interface ChannelReceiver {
        access(all) fun getID(): UInt64
        access(all) fun getName(): String
        access(all) fun addChannelParticipantCapability(_ cap: Capability<&{ChannelParticipant}>)
        access(all) fun toString(): String
    }

    /// API through which a user interfaces with the game, managing both Channel as well as the XPlayer and OPlayer
    /// Capabilities
    ///
    access(all) resource Handle : PlayerReceiver, ChannelReceiver{
        access(self) var name: String
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

        access(all) fun addXPlayerCapability(_ cap: Capability<&{XPlayer}>) {
            pre {
                cap.check(): "Invalid Capability"
                self.xPlayerCaps[cap.borrow()!.getID()] == nil: "Already have Capability for this Board"
                self.oPlayerCaps[cap.borrow()!.getID()] == nil: "Already playing X for this Board"
            }
            self.xPlayerCaps.insert(key: cap.borrow()!.getID(), cap)
        }

        access(all) fun addOPlayerCapability(_ cap: Capability<&{OPlayer}>) {
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

        access(all) fun addChannelParticipantCapability(_ cap: Capability<&{ChannelParticipant}>) {
            pre {
                cap.check(): "Invalid Capability"
                self.channelParticipantCaps[cap.borrow()!.getID()] == nil: "Already have Capability for this Channel"
                cap.borrow()!.getChannelParticipantAddresses().contains(self.owner!.address):
                    "Cannot add a ChannelParticipant Capability for a Channel this account is not a participant of"
            }
            let channelRef = cap.borrow()!
            self.channelParticipantCaps.insert(key: channelRef.getID(), cap)
            
            let participants = channelRef.getChannelParticipantAddresses()
            let other = participants[0] != self.owner!.address ? participants[0] : participants[1]
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

        access(all) fun removeChannelParticipantCapability(id: UInt64): Bool {
            return self.oPlayerCaps.remove(key: id) != nil
        }

        access(all) fun getChannelAddresses(): [Address] {
            return self.channelAddressesToIDs.keys
        }

        access(all) fun toString(): String {
            return self.name.concat("#").concat(self.getID().toString())
        }
    }

    /* Channel */
    //
    /// Enables particpants to start new games with each other
    ///
    access(all) resource interface ChannelParticipant {
        access(all) fun getID(): UInt64
        access(all) fun getChannelParticipantAddresses(): [Address]
        access(all) fun startNewBoard()
        access(all) fun fundChannel(vault: @FungibleToken.Vault)
    }

    /// Channels can be thought of as a Web3 notion of a "game server" where players engage in play on neutral grounds,
    /// storing Board resources and allocating each player's Capability on the Board (pseudo) randomly.
    access(all) resource Channel : ChannelParticipant {
        access(self) let accountCap: Capability<&AuthAccount>
        access(self) let playerCaps: {UInt64: Capability<&{PlayerReceiver}>}

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
        }

        access(all) fun getID(): UInt64 {
            return self.uuid
        }

        access(all) fun getChannelParticipantAddresses(): [Address] {
            return [self.playerCaps.values[0]!.address, self.playerCaps.values[1]!.address]
        }

        /// Creates a new Board, saving in the Channel account, linking and issuing player Capabilities, assigning
        /// X and O (pseudo) randomly
        access(all) fun startNewBoard() {
            let account = self.accountCap.borrow() ?? panic("Problem with AuthAccount Capability")
            let board <-TicTacToe.createEmptyBoard()
            let boardID = board.getID()
            
            account.save(<-board, to: TicTacToe.BoardStoragePath)
            account.link<&{XPlayer}>(TicTacToe.XPlayerPrivatePath, target: TicTacToe.BoardStoragePath)
            account.link<&{OPlayer}>(TicTacToe.OPlayerPrivatePath, target: TicTacToe.BoardStoragePath)

            let xCap = account.getCapability<&{XPlayer}>(TicTacToe.XPlayerPrivatePath)
            let oCap = account.getCapability<&{OPlayer}>(TicTacToe.OPlayerPrivatePath)

            let coinFlip = unsafeRandom() % 2
            let xPlayerID = self.playerCaps.keys[coinFlip]
            let oPlayerID = self.playerCaps.keys[(coinFlip + 1) % 2]

            let xPlayerCap = self.playerCaps[xPlayerID]!
            let oPlayerCap = self.playerCaps[oPlayerID]!

            xPlayerCap.borrow()?.addXPlayerCapability(xCap)
                ?? panic("Problem with PlayerReceiver Capability for player with Address: ".concat(xPlayerCap.address.toString()))
            oPlayerCap.borrow()?.addOPlayerCapability(oCap)
                ?? panic("Problem with PlayerReceiver Capability for player with Address: ".concat(oPlayerCap.address.toString()))

            emit BoardAddedToChannel(boardID: boardID, channelID: self.getID(), xPlayerAddress: xPlayerCap.address, oPlayerAddress: oPlayerCap.address)
        }

        /// Allows participants to fund this Channel's account
        access(all) fun fundChannel(vault: @FungibleToken.Vault) {
            emit ChannelFunded(id: self.getID(), address: self.owner!.address, amount: vault.balance)
            let accountRef: &AuthAccount = self.accountCap.borrow()!
            accountRef.borrow<&FungibleToken.Vault>(from: /storage/flowTokenVault)!.deposit(
                from: <-vault
            )
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

    /* Admin */
    //
    /// Enables update on minimumFundingAmount
    pub resource Admin {
        pub fun setMinimumFundingAmount(_ new: UFix64) {
            TicTacToe.minimumFundingAmount = new
            emit MinimumFundingAmountUpdated(newAmount: new)
        }
    }

    /* Public creation methods */
    //
    /// Returns a new Board resource
    ///
    access(all) fun createEmptyBoard(): @Board {
        let board <-create Board()
        emit BoardCreated(id: board.getID())
        return <- board
    }
    
    /// Returns a new Handle resource
    ///
    access(all) fun createHandle(name: String): @Handle {
        let handle <-create Handle(name: name)
        emit HandleCreated(id: handle.getID(), name: name)
        return <- handle
    }

    /* Resolution logic */
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

        self.AdminStoragePath = /storage/TicTacToeAdmin
        self.BoardStoragePath = /storage/TicTacToeBoard
        self.XPlayerPrivatePath = /private/TicTacToeXPlayer
        self.OPlayerPrivatePath = /private/TicTacToeOPlayer
        self.HandleStoragePath = /storage/TicTacToeHandle
        self.PlayerReceiverPublicPath = /public/TicTacToePlayerReceiver
        self.ChannelReceiverPublicPath = /public/TicTacToeChannelReceiver
        self.ChannelStoragePath = /storage/TicTacToeChannel
        self.ChannelAccountPath = /private/ChannelAccountCapability
        self.ChannelParticipantsPrivatePath = /private/TicTacToeChannelParticipant

        self.account.save(<-create Admin(), to: self.AdminStoragePath)
    }
}