pragma solidity >=0.4.22 <0.7.0;
//pragma experimental SMTChecker;

contract LoanContract {
	address payable public lender;
    address payable public renter;

    uint public paymentAmount;
    uint public paymentStored;
    uint public renterCollateral;
    uint public lenderCollateral;

    uint public rentPeriod;
    uint public graceTime;
    uint public deadline;
    uint public graceDeadline;

    uint public lenderBalance;
    uint public renterBalance;

	enum State { Created, Collaterized, Transferring, Loaned, ReturnScheduled, Returned, Refund, Inactive, Late } //late is unused, refunded is kinda used but maybe it shouldn't be
	//enum //standing { Friendly, Unconfirmed, Dispute, Unresponsive } //still not sure what I want this for, but it does kinda leave metadata for postmortum
    State public state;
    ////standing public //standing;

    modifier onlyRenter() {
        require(
            msg.sender == renter,
            "Only the renter can call this."
        );
        _;
    }

    modifier onlyLender() {
        require(
            msg.sender == lender,
            "Only the lender can call this."
        );
        _;
    }

    modifier  notLender() { 
    	require(
            msg.sender != lender,
            "Don't rent to yourself."
        ); 
    	_; 
    }
    
    modifier onlyMemeber() { 
        require (
            msg.sender == renter || msg.sender == lender,
            "You are not a participant in the contract."
        ); 
        _; 
    }

    modifier inState(State _state) {
        require(
            state == _state,
            "Invalid state. Please check that you are allowed to run this method at this time."
        );
        _;
    }

    modifier timedOut() { 
    	require(
    		now >= deadline,
    		"You must wait until after the deadline."
    	); 
    	_; 
    }

    modifier notTimedOut() {
    	require(
    		now < deadline,
    		"The deadline has passed."
    	); 
    	_;
    }

    modifier inGracePeriod() { 
    	require (
    		now < graceDeadline,
    		"You missed the grace period."
    	);
    	_; 
    }

    modifier inDisputePeriod() { 
        require (
            now - graceTime < graceDeadline,
            "You missed the Dispute period."
        );
        require (
            now >= graceDeadline,
            "Wait until the grace period ends."
        );
        _; 
    }

    modifier afterDisputePeriod() { 
        require (
            now - graceTime >= graceDeadline,
            "Wait for the dispute period to end."
        );
        _; 
    }

    modifier afterGracePeriod() { 
    	require (
    		now >= graceDeadline,
    		"Wait until the grace period ends."
    	); 
    	_; 
    }

    event Created(); 
    event ContractFunded(); 

    event InvitationToTrade();
    event ItemLoaned();
    event ReturnScheduled();
    event ItemReturned();

    event RenterWithdrew();
    event LenderWithdrew();
    event FinishedSuccessfully();

    event Aborted();
    event LastChanceAborted();
    event LateAborted();

    event LenderInactivity();
    event RenterInactivity();
    event PurchaseForced();
    event LenderDisputed();

    /// Here the renter sets the terms of the rental agreement.
    /// They initialize with their collateral and set the following variables
    /// paymentAmount: the cost they wish for rental
    /// renterCollateral: the amount of collateral they wish for the renter to provide
    /// rentPeriod: the approximate amount of time for renting (+/- a grace period or two)
    /// deadline: the time at which the renter must have their item back by
    /// graceTime: how long will people be given to dispute messages the other party sends to the contract
    /// as well as time to take the actions required to transfer the item back and forth
    constructor(uint _requiredPayment, uint _requiredRenterCollateral, uint _rentTime, uint _deadline, uint _graceTimePeriod) public payable {
        require (
            msg.value <= _requiredRenterCollateral && 2*_requiredPayment < msg.value,
            "Please make smart choices in your payment scheme. Refer to documentation for suggestions."
        );
        
        require(
            now + _rentTime + 2*_graceTimePeriod < _deadline,
            "Invalid timeframe, allow for two grace periods between the end of the rental period and the deadline."
        );

        lenderBalance = 0;
        renterBalance = 0;

        lender = msg.sender;
        lenderCollateral = msg.value;
        
        renterCollateral = _requiredRenterCollateral;
        paymentAmount = _requiredPayment;
        
        rentPeriod = _rentTime;
        deadline = _deadline;
        graceTime = _graceTimePeriod;

        emit Created();
    }

    /// This is how the renter enters the contract
    function fundAsRenter()
    	public
	    payable
	    notLender
	    inState(State.Created)
	{
		require(
			(now + rentPeriod < deadline),
			"Not enough remaining time to rent."
		);
		require(
			msg.value >= renterCollateral + paymentAmount,
			"Not enough funds for payment and collateral."
		);

		state = State.Collaterized;

		renter = msg.sender; //think about putting something here to account for if there somehow is already a renter
		paymentStored = msg.value - renterCollateral;
		deadline = now + rentPeriod;
		graceDeadline = now + graceTime;
		emit ContractFunded();
	}

    /// Confirm that you (the lender) will send the item.
    /// This begins the transfer period which is graceTime in length
    function Giving()
        public
        onlyLender
        inState(State.Collaterized)
        afterGracePeriod
    {
        state = State.Transferring;
        graceDeadline = now + graceTime;
        //standing = //standing.Unconfirmed;
        emit InvitationToTrade();
    }

    /// Confirm receipt of item within grace period and end grace period
    function Recieved()
    	public
    	onlyRenter
    	inState(State.Transferring)
    	inGracePeriod
    {
    	state = State.Loaned;
    	graceDeadline = now;
    	//standing = //standing.Friendly;
    	emit ItemLoaned();
    }


    /////////////////////////////////////////////////////
    /////////  This is when the renting happens  ////////
    /////////////////////////////////////////////////////


    /// The Lender schedules a return with one grace period of the deadline
    /// This begins the transfer period which is graceTime in length
    function ScheduleReturn()
    	public
    	onlyLender
    	inState(State.Loaned)
    	notTimedOut
    {
    	require(
    		now + 2*graceTime > deadline,
    		"Return schedueld too early, wait until within two grace periods before the deadline."
    	);
    	
    	state = State.ReturnScheduled;
    	graceDeadline = now + graceTime;
    	deadline = now + 2*graceTime;
    	//standing = //standing.Unconfirmed;
    	emit ReturnScheduled();
    }

    /// Confirm that you (the renter) returned the item.
    function ConfirmReturned()
    	public
    	onlyRenter
    	inState(State.ReturnScheduled)
    	inGracePeriod
    {
    	state = State.Returned;
    	graceDeadline = now + graceTime;
    	emit ItemReturned();
    }


    function Finalize()
        public
        onlyMemeber
        inState(State.Returned)
        afterGracePeriod
    {
        state = State.Inactive;
        lenderBalance = lenderCollateral + paymentStored;
        renterBalance = renterCollateral;
        emit FinishedSuccessfully();
    }

    /// This pays and refunds the lender whatever they're owed
	function withdrawLender()
        public
        onlyLender
        inState(State.Inactive)
        afterGracePeriod
    {
        uint amount = lenderBalance;
        lenderBalance = 0;
    	lender.transfer(amount);
        emit LenderWithdrew();
    }

    /// This function refunds the renter whatever they're owed
    function withdrawRenter()
        public
        onlyRenter
        inState(State.Inactive)
        afterGracePeriod
    {
        uint amount = renterBalance;
        renterBalance = 0;
        renter.transfer(amount);
        emit RenterWithdrew();
    }

    /////////////////////////////////////////////////////
    /// This section starts the dispute framework ///////
    /////////////////////////////////////////////////////

    /// Abort the rental if no one comes in as renter to fund the contract.
    /// Can only be called by the lender before the contract is put in motion.
    function abortNoInterest()
        public
        onlyLender
        inState(State.Created)
    {
        state = State.Inactive;
        lenderBalance = address(this).balance;
        emit Aborted();
    }

    /// Abort during scheduling
    /// Works within the grace period of the Renter funding
    /// Either person can back out during this period
    /// The period should be used for communication and scheduling
    function abortLastChance()
        public
        onlyMemeber
        inState(State.Collaterized)
        inGracePeriod
    {
        state = State.Inactive;
        renterBalance = renterCollateral + paymentStored;
        lenderBalance = lenderCollateral;
        emit LastChanceAborted();
    }

    /// If the Renter does not report a receipt of the item, the Lender has a chance to accuse the Renter of accepting the item and pretending they didn't
    /// To pervent misuse, this breaking of the contract costs everything from both parties.
    /// From a utility standpoint, this worsens the outcome for the lender, but not significantly
    /// and is the only way to make the outcome of the renter negative (given sensible paymentAmount and collateral) 
    function blameRenterRecieve()
    	public
    	onlyLender
    	inState(State.Transferring)
    	inDisputePeriod
    {
    	state = State.Inactive;
    	emit LenderDisputed();
    }

    /// If during the transfer period, the Lender cannot give, then they can end the transaction before the grace period ends
    /// Can be used maliciously but only to take same money from both.
    /// This is the lender's safeguard to renter cheating by refusing the item, and should not be used if the item was actually given.
    /// This is here currently as a seperate option for the Lender to give them an alternative to blameRenterRecieve in the case of external desire for maliciousness
    /// This could be replaced by reputation system and isn't useful in any strategy
    function blameCannotGive()
    	public
    	onlyLender
    	inState(State.Transferring)
    	inDisputePeriod
    {
    	state = State.Inactive;
    	lenderBalance = lenderCollateral - 2*paymentAmount;
    	renterBalance = renterCollateral - paymentAmount;
    	emit RenterInactivity();
    }

    /// If the Lender is truly unresponsive, the Renter has a failsafe with a full refund for them.
    /// This acts as a suggested ending for the Lender if they have a not-so-bad experience with the Renter but cannot trade.
    /// Either person is able to call this to allow for things to end.
    /// This function is actually one of the main "economic security risks"
    /// However it might be a reasonable request from users to have this
    /// It really opens things to coersion and this function should be depreciated
    function abortCouldntGive()
    	public
    	onlyMemeber
    	inState(State.Transferring)
    	afterDisputePeriod
    {
    	state = State.Inactive;
    	lenderBalance = lenderCollateral;
    	renterBalance = renterCollateral + paymentStored;
    	emit LateAborted();
    }

    /// If the Lender is truly unresponsive, the Renter has a failsafe with a full refund for them
    /// and a partial slashing of the Lender
    /// This would be the fallback for removing abortCounldntGive but might need to incorporate a larger penalty
    function abortTimeoutGiving()
    	public
    	onlyRenter
    	inState(State.Collaterized)
    	afterDisputePeriod
    {
    	state = State.Inactive;
    	lenderBalance = lenderCollateral - paymentAmount;
    	renterBalance = renterCollateral + paymentStored;
    	emit LenderInactivity();
    }

    /// If the lender refuses to initiate takeback of the item
    /// they can complain to invoke bought rented item dispute
    /// This is designed to be a bad deal for both with minimal losses
    /// See the documentation for suggested bounds on collateral and item value for further explanation
    function abortTimeoutForcePurchace()
        public
        onlyMemeber
        inState(State.ReturnScheduled)
        timedOut
        afterGracePeriod
    {
        state = State.Inactive;
        renterBalance = renterCollateral - lenderCollateral - paymentAmount;
        lenderBalance = 2*lenderCollateral - paymentAmount;
        emit PurchaseForced();
    }

    /// If the Renter falsely claims they returned
    /// The Lender is given the option of a scorched earth abort
    /// To dissuade malicious use of this, this costs everything from all parties
    function blameFalseReturn()
        public
        onlyLender
        inState(State.Returned)
        inGracePeriod
    {
        state = State.Inactive;
        emit LenderDisputed();
    }

    /// If an inattentive or dumb malicious lender stops responding
    /// The renter gets everything back and may keep the item.
    function abortTimeoutReturnScheduling()
        public
        onlyRenter
        inState(State.Loaned)
        timedOut
        afterGracePeriod
    {
        state = State.Inactive;
        renterBalance = renterCollateral + paymentAmount;
        lenderBalance = lenderCollateral;
        emit LenderInactivity();
    }

}