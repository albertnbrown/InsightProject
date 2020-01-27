pragma solidity >=0.4.22 <0.7.0;

contract LoanContract {
	address payable public lender;
    address payable public renter;

    uint paymentAmount;
    uint paymentStored;
    uint renterCollateral;
    uint lenderCollateral;

    uint rentPeriod;
    uint graceTime;
    uint deadline;
    uint graceDeadline;

    bool lenderPaid;
    bool renterRefunded;

	enum State { Created, Collaterized, Transferring, Loaned, ReturnScheduled, Returned, Refunded, Inactive, Late } //late is unused, refunded is kinda used but maybe it shouldn't be
	enum Standing { Friendly, Unconfirmed, Dispute, Unresponsive } //still not sure what I want this for, but it does kinda leave metadata for postmortum
    State public state;
    Standing public standing;

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

    modifier afterGracePeriod() { 
    	require (
    		now >= graceDeadline,
    		"Wait until the grace period ends."
    	); 
    	_; 
    }

    event Created();
    event ContractFunded();
    event Aborted();
    event LastChanceAborted();
    event InvitationToTrade();
    event ItemLoaned();
    event ReturnScheduled();
    event ItemReturned();
    event RenterRefunded();
    event LenderPaid();
    event RenterInactivity();
    event LenderInactivity();
    event RenterDisputed();
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
        lender = msg.sender;
        lenderCollateral = msg.value;
        
        renterCollateral = _requiredRenterCollateral;
        paymentAmount = _requiredPayment;


        require (
        	paymentAmount < renterCollateral && paymentAmount < lenderCollateral,
        	"Please make smart choices in your payment scheme. Refer to documentation for suggestions."
        );
        

        require(
        	now + _rentTime + 2*_graceTimePeriod < _deadline,
        	"Invalid timeframe, allow for two grace periods between the end of the rental period and the deadline."
        );
        
        rentPeriod = _rentTime;
        deadline = _deadline;
        graceTime = _graceTimePeriod;

        lenderPaid = false;
        renterRefunded = false;

        emit Created();
    }

    /// Abort the purchase and reclaim the ether.
    /// Can only be called by the lender before
    /// the contract is put in motion.
    function abort()
        public
        onlyLender
        inState(State.Created)
    {
        emit Aborted();
        state = State.Inactive;
        lender.transfer(address(this).balance);//maybe add the safeguard of transferring to lender the amount they're owned and send to renter the rest
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

    /// Fuzzy Abort
    /// Works within the grace period of the Renter funding
    /// Either person can back out during this period
    /// The period should be used for communication and scheduling
    function fuzzyAbort()
    	public
        onlyMemeber
    	inState(State.Collaterized)
    	inGracePeriod
    {
    	state = State.Inactive;
    	renter.transfer(renterCollateral + paymentStored);
    	lender.transfer(address(this).balance);
    	emit LastChanceAborted();
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
        standing = Standing.Unconfirmed;
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
    	standing = Standing.Friendly;
    	emit ItemLoaned();
    }


    /////////////////////////////////////////////////////
    /////////  This is when the renting happens  ////////
    /////////////////////////////////////////////////////


    /// The Lender schedules a return with one grace period of the deadline
    /// This begins the transfer period which is graceTime in length
    function scheduleReturn()
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
    	standing = Standing.Unconfirmed;
    	emit ReturnScheduled();
    }

    /// Confirm that you (the renter) returned the item.
    function confirmReturned()
    	public
    	onlyRenter
    	inState(State.ReturnScheduled)
    	inGracePeriod
    {
    	state = State.Returned;
    	graceDeadline = now + graceTime;
    	standing = Standing.Friendly;
    	emit ItemReturned();
    }

    /// This pays and refunds the lender
	function payLender()
        public
        onlyLender
        inState(State.Returned)
        afterGracePeriod
    {
    	require (
    		!lenderPaid,
    		"Nice try, buck-o"
    	);
        if(renterRefunded){
            state = State.Refunded;
        }
        lenderPaid = true;
    	lender.transfer(lenderCollateral + paymentStored);
        emit LenderPaid();
    }

    /// This function refunds the renter
    function refundRenterCollateral()
        public
        onlyRenter
        inState(State.Returned)
        afterGracePeriod
    {
    	require (
    		!renterRefunded,
    		"Nice try, buck-o"
    	);
        if(lenderPaid){
            state = State.Refunded;
        }
        renterRefunded = true;
    	renter.transfer(renterCollateral);
        emit RenterRefunded();
    }

    /////////////////////////////////////////////////////
    /// This section starts the dispute framework ///////
    /////////////////////////////////////////////////////

    /// If an inattentive or dumb malicious renter stops responding
    /// The lender is then paid the maximum amount for the item
    function neverReturned()
    	public
    	onlyLender
    	inState(State.ReturnScheduled)
    	timedOut
    	afterGracePeriod
    {
    	state = State.Inactive;
    	standing = Standing.Unresponsive;
    	lender.transfer(address(this).balance);
    	emit RenterInactivity();
    }

    /// If the lender refuses to initiate takeback of the item
    /// they can complain to invoke bought rented item dispute
    /// here, the item is bought, in the eyes of the renter, for the price of renting plus price of collateral
    /// in the eyes of the lender, it is bought for the price of the renting cost
    /// This is a bad deal for both with minimal losses
    function cannotReturn()//needs a better name
    	public
    	onlyRenter
    	inState(State.Loaned)
    	timedOut
    	afterGracePeriod
    {
    	state = State.Inactive;
    	standing = Standing.Unresponsive;
    	renter.transfer(paymentAmount);
    	lender.transfer(paymentAmount);
    	emit RenterDisputed();
    }

    /// If the Lender isn't giving the Renter the chance to return
    /// The Renter is given the option of a scorched earth abort to avoid neverReturned()
    /// To dissuade malicious use of this, this costs everything from all parties
    function blameReturn()//I am highly concerned about this method. I'm not sure it really should need to exist. This makes me reconsider the setup of the transferring system and if it should be that way.
    	public
    	onlyRenter
    	inState(State.ReturnScheduled)
    	inGracePeriod
    {
    	state = State.Inactive;
    	standing = Standing.Dispute;
    	emit RenterDisputed();
    }

    /// If the Renter falsely claims they returned
    /// The Lender is given the option of a scorched earth abort
    /// To dissuade malicious use of this, this costs everything from all parties
    /// This needs work, probably
    function claimFalseReturn()
    	public
    	onlyLender
    	inState(State.Returned)
    	inGracePeriod
    {
    	state = State.Inactive;
    	standing = Standing.Dispute;
    	emit LenderDisputed();
    }

    /// If, after collaterized, the giving process does not go well for the Renter
    /// Then they are given the option to scorched earth abort
    /// To dissuade malicious use of this, this costs everything from all parties
    function blameGive()//name is fine but look to other name for new name paradigm
    	public
    	onlyRenter
    	inState(State.Transferring)
    	inGracePeriod
    {
    	state = State.Inactive;
    	standing = Standing.Dispute;
    	emit RenterDisputed();
    }

    /// If the grace period for initial transferring expires and the renter does not signal success or blame
    /// Then it is likely that the renter didn't respond as they were given chance to both positively and negatively
    /// Therefore a partial abort is done with payment slashed
    function cannotGive()
    	public
    	onlyLender
    	inState(State.Transferring)
    	afterGracePeriod
    	notTimedOut
    {
    	state = State.Inactive;
    	standing = Standing.Unresponsive;
    	lender.transfer(lenderCollateral);
    	renter.transfer(renterCollateral);
    	emit RenterInactivity();
    }

    /// If the Lender is truly unresponsive, the Renter has a failsafe with a full refund for them
    /// and a partial slashing of the Lender
    function timeOutAfterGive()
    	public
    	onlyRenter
    	inState(State.Transferring)
    	afterGracePeriod
    	timedOut
    {
    	state = State.Inactive;
    	standing = Standing.Unresponsive;
    	lender.transfer(lenderCollateral - paymentAmount);
    	renter.transfer(renterCollateral + paymentStored);
    	emit LenderInactivity();
    }

    /// If the Lender is truly unresponsive, the Renter has a failsafe with a full refund for them
    /// and a partial slashing of the Lender
    function timeOutOnGive()
    	public
    	onlyRenter
    	inState(State.Collaterized)
    	afterGracePeriod
    	timedOut
    {
    	state = State.Inactive;
    	standing = Standing.Unresponsive;
    	lender.transfer(lenderCollateral - paymentAmount);
    	renter.transfer(renterCollateral + paymentStored);
    	emit LenderInactivity();
    }
}