asm fun myCode(): Cell { MYCODE }

@interface("org.ton.jetton.wallet")
contract JettonWallet with Ownable {
    balance: Int as coins;
    owner: Address;
    master: Address;
    const minTonsForStorage: Int = ton("0.019");
    const gasConsumption: Int = ton("0.013");

    init(owner: Address, master: Address) {
        self.balance = 0;
        self.owner = owner;
        self.master = master;
    }


    receive(msg: TokenTransfer) {
        self.requireOwner();

        let final: Int = (((10 * 2 + 2 * self.gasConsumption) + self.minTonsForStorage) + msg.forward_ton_amount); // Gas checks, forward_ton = 0.152

        //Context() returns Structure with info about incoming message
        require(context().value > final, "Unsufficient amount of TON attached");

        self.balance -= msg.amount;

        //coins type is unsigned type, so
        //self.balance is unsigned when storing and loading (msg.amount is unsigned too),
        //however when doing calculations it's value may be negative, so the check is correct
        require(self.balance >= 0, "Invalid balance");
        let init: StateInit = initOf JettonWallet(msg.destination, self.master);

        let wallet_address: Address = contractAddress(init);
        send(SendParameters{
        to: wallet_address,
        value: 0,
        mode: SendRemainingValue,
        bounce: true,
        body: TokenTransferInternal {
        query_id: msg.query_id,
        amount: msg.amount,
        from: self.owner,
        response_destination: msg.response_destination,
        forward_ton_amount: msg.forward_ton_amount,
        forward_payload: msg.forward_payload
        }.toCell(),
        code: init.code,
        data: init.data
        }
        );
    }

    receive(msg: TokenTransferInternal) {
        // This message should come only from master, or from other JettonWallet
        if (sender() != self.master) {
            let init: StateInit = initOf JettonWallet(msg.from, self.master);
            require(contractAddress(init) == sender(), "Sender is not another JettonWallet or JettonMaster");
        }
        // Update balance
        self.balance += msg.amount;

        //Commented require() here because self.balance and msg.amount are coins, so they are unsigned
        //require(self.balance >= 0, "Invalid balance");
        // Get value for gas

        let ctx: Context = context(); //Context of current message
        let msgValue: Int = ctx.value;
        let tonBalanceBeforeMsg = myBalance() - msgValue;
        let storageFee = self.minTonsForStorage - min(tonBalanceBeforeMsg, self.minTonsForStorage);
        msgValue -= (storageFee + self.gasConsumption);
        let fwd_fee: Int = ctx.readForwardFee();


        if (msg.forward_ton_amount > 0) {
            msgValue = ((msgValue - msg.forward_ton_amount) - fwd_fee);
            send(SendParameters{
            to: self.owner,
            value: msg.forward_ton_amount,
            mode: SendPayGasSeparately,
            bounce: false,
            body: TokenNotification{ // 0x7362d09c -- Remind the new Owner
            query_id: msg.query_id,
            amount: msg.amount,
            from: msg.from,
            forward_payload: msg.forward_payload
            }.toCell()
            });
        }
        // 0xd53276db -- Cashback to the original Sender
        if (msg.response_destination != null && msgValue > 0) {
            send(SendParameters{
            to: msg.response_destination!!,
            value: msgValue,
            mode: SendIgnoreErrors, // Jetton transfer is already succeeded, Here was PayGasSeparately in Howard's code
            bounce: false,
            body: TokenExcesses{
            query_id: msg.query_id
            }.toCell()
            }
            );
        }
    }

    receive(msg: TokenBurn){
        self.requireOwner();

        let ctx: Context = context();
        self.balance = (self.balance - msg.amount); // Update balance
        require(self.balance >= 0, "Invalid balance after burn");
        let fwd_fee: Int = ctx.readForwardFee(); // Gas checks
        require(ctx.value > ((fwd_fee + 2 * self.gasConsumption) + self.minTonsForStorage), "Invalid value - Burn");
        // Burn tokens
        send(SendParameters{
        to: self.master,
        value: 0,
        mode: SendRemainingValue,
        bounce: true,
        body: TokenBurnNotification{
        query_id: msg.query_id,
        amount: msg.amount,
        sender: self.owner,
        response_destination: msg.response_destination
        }.toCell()
        }
        );
    }

    bounced(msg: bounced<TokenTransferInternal>){
        self.balance = (self.balance + msg.amount);
    }

    bounced(msg: bounced<TokenBurnNotification>){
        self.balance = (self.balance + msg.amount);
    }

    get fun get_wallet_data(): JettonWalletData {
        return JettonWalletData{
        balance: self.balance,
        owner: self.owner,
        master: self.master,
        code: myCode() //may be raplaced by "initOf JettonDefaultWallet(self.owner, self.master).code"
        };
    }
}