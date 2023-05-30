import "FungibleToken"
import "FlowToken"

access(all) contract TicTacToe {

    access(all) var minimumFundingAmount: UFix64

    /* Common Paths */
    //
    access(all) let BoardStoragePath: StoragePath
    access(all) let XPlayerPrivatePath: PrivatePath
    access(all) let OPlayerPrivatePath: PrivatePath
    access(all) let PlayerChannelStoragePath: StoragePath
    access(all) let PlayerChannelAccountPath: PrivatePath
    access(all) let ChannelParticipantsPrivatePath: PrivatePath
    access(all) let HandleStoragePath: StoragePath
    access(all) let PlayerReceiverPublicPath: PublicPath

    /* TODO: Events */
    //
    // IDEA: Emit human interpretable board state in move events 

    access(all) resource interface XPlayer {
        access(all) fun getBoardID(): UInt64
        access(all) fun markX(row: Int, column: Int)
    }

    access(all) resource interface OPlayer {
        access(all) fun getBoardID(): UInt64
        access(all) fun markO(row: Int, column: Int)
    }
    
    access(all) resource Board {
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

        access(all) fun getBoardID(): UInt64 {
            return self.id
        }

        access(all) fun markX(row: Int, column: Int) {
            self.submitMove(move: true, row: row, column: column)
        }
        access(all) fun markO(row: Int, column: Int) {
            self.submitMove(move: false, row: row, column: column)
        }
        
        access(self) fun submitMove(move: Bool, row: Int, column: Int) {
            pre {
                self.nextMove == move: "This move is not allowed for this round"
                self.board[row][column] == nil: "The cell has already been marked"
                self.inPlay: "Board is no longer in play"
            }
            self.moveCounter = self.moveCounter + 1
            self.board[row][column] = move
            self.nextMove = !move
            if let winner = TicTacToe.getWinner(self.board) {
                self.winner = winner
            }
            if self.moveCounter == 9 || self.winner != nil {
                self.inPlay = false
            }
        }

        access(all) fun isInPlay(): Bool {
            return self.inPlay
        }

        access(all) fun getWinner(): Bool? {
            return self.winner
        }

        access(all) fun getBoard(): [[Bool?]] {
            return self.board
        }
    }

    access(all) resource interface PlayerReceiver {
        access(all) fun getPlayerID(): UInt64
        access(all) fun addXPlayerCapability(_ cap: Capability<&{XPlayer}>)
        access(all) fun addOPlayerCapability(_ cap: Capability<&{OPlayer}>)
    }

    access(all) resource interface ChannelReceiver {
        access(all) fun getPlayerID(): UInt64
        access(all) fun addChannelParticipantCapability(_ cap: Capability<&{ChannelParticipant}>)
    }

    access(all) resource Handle {
        access(self) let xPlayerCaps: {UInt64: Capability<&{XPlayer}>}
        access(self) let oPlayerCaps: {UInt64: Capability<&{OPlayer}>}
        access(self) let channelParticipantCaps: {UInt64: Capability<&{ChannelParticipant}>}
        access(self) let channelAddressesToIDs: {Address: UInt64}

        init() {
            self.xPlayerCaps = {}
            self.oPlayerCaps = {}
            self.channelParticipantCaps = {}
            self.channelAddressesToIDs = {}
        }

        access(all) fun getPlayerID(): UInt64 {
            return self.uuid
        }

        access(all) fun addXPlayerCapability(_ cap: Capability<&{XPlayer}>) {
            pre {
                cap.check(): "Invalid Capability"
                self.xPlayerCaps[cap.borrow()!.getBoardID()] == nil: "Already have Capability for this Board"
                self.oPlayerCaps[cap.borrow()!.getBoardID()] == nil: "Already playing X for this Board"
            }
            self.xPlayerCaps.insert(key: cap.borrow()!.getBoardID(), cap)
        }

        access(all) fun addOPlayerCapability(_ cap: Capability<&{OPlayer}>) {
            pre {
                cap.check(): "Invalid Capability"
                self.oPlayerCaps[cap.borrow()!.getBoardID()] == nil: "Already have Capability for this Board"
                self.xPlayerCaps[cap.borrow()!.getBoardID()] == nil: "Already playing O for this Board"
            }
            self.oPlayerCaps.insert(key: cap.borrow()!.getBoardID(), cap)
        }

        access(all) fun borrowChannelParticpantByAddress(_ address: Address): &{ChannelParticipant} {
            return self.channelParticipantCaps[self.channelAddressesToIDs[address]!]!.borrow()!
        }
    }

    access(all) resource interface ChannelParticipant {
        access(all) fun getChannelID(): UInt64
        access(all) fun startNewGame()
    }

    access(all) resource PlayerChannel : ChannelParticipant {
        access(self) let accountCap: Capability<&AuthAccount>
        access(self) let playerCaps: {UInt64: Capability<&{PlayerReceiver}>}

        init(accountCap: Capability<&AuthAccount>, player1: Capability<&{PlayerReceiver}>, player2: Capability<&{PlayerReceiver}>) {
            pre {
                player1.check(): "Invalid Player 1 Capability"
                player2.check(): "Invalid Player 2 Capability"
            }
            self.accountCap = accountCap
            self.playerCaps = {
                player1.borrow()!.getPlayerID(): player1,
                player2.borrow()!.getPlayerID(): player2
            }
        }

        access(all) fun getChannelID(): UInt64 {
            return self.uuid
        }

        access(all) fun startNewGame() {
            let account = self.accountCap.borrow() ?? panic("Problem with AuthAccount Capability")
            account.save(<-create Board(), to: TicTacToe.BoardStoragePath)
            account.link<&{XPlayer}>(TicTacToe.XPlayerPrivatePath, target: TicTacToe.BoardStoragePath)
            account.link<&{OPlayer}>(TicTacToe.OPlayerPrivatePath, target: TicTacToe.BoardStoragePath)

            let xCap = account.getCapability<&{XPlayer}>(TicTacToe.XPlayerPrivatePath)
            let oCap = account.getCapability<&{OPlayer}>(TicTacToe.OPlayerPrivatePath)

            let coinFlip = unsafeRandom() % 2
            let xPlayerID = self.playerCaps.keys[coinFlip]
            let oPlayerID = self.playerCaps.keys[(coinFlip + 1) % 2]

            self.playerCaps[xPlayerID]!.borrow()?.addXPlayerCapability(xCap)
                ?? panic("Problem with PlayerReceiver Capability for ID: ".concat(xPlayerID.toString()))
            self.playerCaps[oPlayerID]!.borrow()?.addOPlayerCapability(oCap)
                ?? panic("Problem with PlayerReceiver Capability for ID: ".concat(oPlayerID.toString()))
        }
    }

    access(all) fun createPlayerChannel(
        playerReceiver1: Capability<&{PlayerReceiver}>,
        playerReceiver2: Capability<&{PlayerReceiver}>,
        channelReceiver1: &{ChannelReceiver},
        channelReceiver2: &{ChannelReceiver},
        fundingVault: @FungibleToken.Vault
    )  {
        pre {
            fundingVault.balance == self.minimumFundingAmount: "Minimum funding amount not met"
            playerReceiver1.check(): "Invalid playerReceiver1 Capability"
            playerReceiver2.check(): "Invalid playerReceiver2 Capability"
            playerReceiver1.borrow()!.getPlayerID() != playerReceiver2.borrow()!.getPlayerID() &&
            channelReceiver1.getPlayerID() != channelReceiver2.getPlayerID():
                "Can't play against yourself"
            playerReceiver1.borrow()!.getPlayerID() == channelReceiver1.getPlayerID():
                "playerReceiver1 and channelReceiver1 must resolve to same Handle!"
            playerReceiver2.borrow()!.getPlayerID() == channelReceiver2.getPlayerID():
                "playerReceiver2 and channelReceiver2 must resolve to same Handle!"
        }

        let vaultRef = self.account.borrow<&FungibleToken.Vault>(from: /storage/flowTokenVault)!
        let fundingBalance = fundingVault.balance
        vaultRef.deposit(from: <-fundingVault)

        let neutralAccount = AuthAccount(payer: self.account)
        neutralAccount.borrow<&FungibleToken.Vault>(from: /storage/flowTokenVault)!.deposit(
            from: <-vaultRef.withdraw(amount: fundingBalance)
        )

        let accountCap = neutralAccount.linkAccount(self.PlayerChannelAccountPath)!
        neutralAccount.save(
            <-create PlayerChannel(
                accountCap: accountCap,
                player1: playerReceiver1,
                player2: playerReceiver2
            ),
            to: self.PlayerChannelStoragePath
        )
        neutralAccount.link<&{ChannelParticipant}>(self.ChannelParticipantsPrivatePath, target: self.PlayerChannelStoragePath)

        let channelParticipantCap = neutralAccount.getCapability<&{ChannelParticipant}>(self.ChannelParticipantsPrivatePath)
        channelReceiver1.addChannelParticipantCapability(channelParticipantCap)
        channelReceiver2.addChannelParticipantCapability(channelParticipantCap)
    }


    access(all) fun createEmptyBoard(): @Board {
        return <-create Board()
    }

    access(all) fun createNewHandle(): @Handle {
        return <-create Handle()
    }

    /// Totally not efficient, but it works
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

    access(self) fun checkRows(_ board: [[Bool?]]): Bool? {
        for r in board {
            if r[0] != nil && (r[0] == r[1] && r[1] == r[2]) {
                return r[0]
            }
        }
        return nil
    }

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

    access(self) fun checkDiagonal(_ board: [[Bool?]]): Bool? {
        if board[0][0] != nil && (board[0][0] == board[1][1] && board[1][1] == board[2][2]) {
            return board[0][0]
        }
        return nil
    }

    access(account) fun updateMinimumFundingAmount(amount: UFix64) {
        self.minimumFundingAmount = amount
    }

    init() {
        self.minimumFundingAmount = 1.0

        self.BoardStoragePath = /storage/TicTacToeBoard
        self.XPlayerPrivatePath = /private/TicTacToeXPlayer
        self.OPlayerPrivatePath = /private/TicTacToeOPlayer
        self.HandleStoragePath = /storage/TicTacToeHandle
        self.PlayerReceiverPublicPath = /public/TicTacToePlayerReceiver
        self.PlayerChannelStoragePath = /storage/TicTacToePlayerChannel
        self.PlayerChannelAccountPath = /private/PlayerChannelAccountCapability
        self.ChannelParticipantsPrivatePath = /private/TicTacToePlayerChannel
    }
}