//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.14;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title A Loan Contract for requesting Loans and make Loan offeres (single and batched)
/// @author Lendies team
/// @notice This contract can be used for requesting loans and pay this loans, and accepts any ERC20 token as payment
contract LendiesCore {
    mapping(address => mapping(uint256 => LoanRequest)) public LoanRequests;
    mapping(address => uint256) failedTransferCredits;
    //Each LoanRequest is unique to each TradeableCashflow (NFT) (contract + id pairing).
    struct LoanRequest {
        //map token ID to

        uint32 newOfferPeriod; //Increments the length of time the LoanRequest is open in which a new offer can be made after each offer.
        uint64 requestEnd;
        uint128 maxInterestRate;
        uint128 instantAcceptableInterestRate; //sets an interest rate, which if offered, will be taken instantly
        uint128 lowestInterestRateOffered;
        uint128 loanAmount;
        uint128 loanDurationInSeconds; //Amount of time in which borrower wants to repay loaner
        address bestLoaner; //loaner who has offered lowest interest rate until that moment
        address borrower;
        address whitelistedLoaner; //The borrower can specify a whitelisted address for a loaner (this is effectively a direct loan).
        address paymentRecipient; //The loaner can specify a recipient for the NFT if their offer is successful (Borrower will pay debt to this address).
        address ERC20Token; // The Borrower can specify an ERC20 token that he wants to receive.
        address[] feeRecipients;
        uint32[] feePercentages;
    }
    /*
     * Default values that are used if not specified by the borrower.
     */
    uint32 public minimumMaxInterestRate; //Should users be able to set any interest rates? ex: 0% interest rate? 1000% interest rate?
    uint32 public defaultnewOfferPeriod;

    /*╔═════════════════════════════╗
      ║           EVENTS            ║
      ╚═════════════════════════════╝*/

    event RequestCreated(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        address borrower,
        address erc20Token,
        uint128 maxInterestRate,
        uint128 instantOfferInterestRate,
        uint32 newOfferPeriod,
        address[] feeRecipients,
        uint32[] feePercentages
    );

    event OfferAccepted(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        address borrower,
        address erc20Token,
        uint128 instantAcceptableInterestRate,
        address whitelistedLoaner,
        address[] feeRecipients,
        uint32[] feePercentages
    );

    event OfferMade(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        address loaner,
        uint256 ethAmount,
        address erc20Token,
        uint256 tokenAmount
    );

    event RequestPeriodUpdated(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        uint64 requestEndPeriod
    );

    event TradeableCashTransferedAndLoanerPaid(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        address borrower,
        uint128 lowestInterestRateOffered,
        address bestLoaner,
        address paymentRecipient
    );

    event RequestSettled(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        address requestSettler
    ); //when emitting this, also open a stream toowner of tradeableCashstream

    event RequestWithdrawn(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        address borrower
    );

    event OfferWithdrawn(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        address bestLoaner
    );

    event WhitelistedLoanerUpdated(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        address newWhitelistedLoaner
    );

    event MaxInterestRateUpdated(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        uint256 newMaxInterestRate
    );

    event instantAcceptableInterestRateUpdated(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId,
        uint128 newAcceptableInterestRate
    );
    event LowestInterestRateTaken(
        address tradeableCashflowAddress,
        uint256 tradeableCashflowId
    );
    /**********************************/
    /*╔═════════════════════════════╗
      ║             END             ║
      ║            EVENTS           ║
      ╚═════════════════════════════╝*/
    /**********************************/
    /*╔═════════════════════════════╗
      ║          MODIFIERS          ║
      ╚═════════════════════════════╝*/

    modifier isRequestNotStartedByOwner(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) {
        require(
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .borrower != msg.sender,
            "Request already started by owner"
        );

        if (
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .borrower != address(0)
        ) {
            require(
                msg.sender ==
                    IERC721(_tradeableCashflowAddress).ownerOf(
                        _tradeableCashflowId
                    ),
                "Sender doesn't own TradeableCashflowNFT"
            );

            _resetRequest(_tradeableCashflowAddress, _tradeableCashflowId);
        }
        _;
    }

    modifier requestOngoing(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) {
        require(
            _isRequestOngoing(_tradeableCashflowAddress, _tradeableCashflowId),
            "Request has ended"
        );
        _;
    }

    modifier borrowAmountGreaterThanZero(uint256 _borrowAmount) {
        require(_borrowAmount > 0, "Borrow amount cannot be 0");
        _;
    }

    /*
     * The minimum price must be 80% of the buyNowPrice(if set).
     */

    /*
    modifier maxInterestRateIsLowerThanInstantAcceptable(
        uint128 _instantAcceptableInterestRate,
        uint128 _maxInterestRate
    ) {
        require(
            _instantAcceptableInterestRate == 1000 ||
                _getPortionOfOffer(_instantAcceptableInterestRate, maximumMaxInterestRatePercentage) >=
                _maxInterestRate,
            "instantAcceptableInterestRate > 80% maxInterestRate"
        );
        _;
    }*/

    modifier notBorrower(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) {
        require(
            msg.sender !=
                LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                    .borrower,
            "Borrower cannot offer on own request"
        );
        _;
    }
    modifier onlyBorrower(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) {
        require(
            msg.sender ==
                LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                    .borrower,
            "Only borrower"
        );
        _;
    }
    /*
     * The offer interest rate was either equal the instatAcceptanceInterestRate
     * or it must be lower than the previous offer.
     */
    modifier offerAmountMeetsOfferRequirements(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        uint128 _tokenAmount,
        uint128 _offeredInterestRate
    ) {
        require(
            _doesOfferMeetOfferRequirements(
                _tradeableCashflowAddress,
                _tradeableCashflowId,
                _tokenAmount,
                _offeredInterestRate
            ),
            "Funds or interest rate requirements not met to offer on Request"
        );
        _;
    }
    // check if Loaner can offer on this request.
    modifier onlyApplicableLoaner(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) {
        require(
            !_isWhitelistedSale(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            ) ||
                LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                    .whitelistedLoaner ==
                msg.sender,
            "Only the whitelisted loaner"
        );
        _;
    }

    modifier maximumInteresRateOffered(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) {
        require(
            !_isMaximumInterestRateOffered(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            ),
            "The request has a valid offer made"
        );
        _;
    }

    /*
     * Payment is accepted if the payment is made in the ERC20 token or ETH specified by the borrower.
     * Early offers on requests not yet up published must be made in ETH. (remember ath the end, "requests" are NFTs)
     */
    modifier paymentAccepted(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _erc20Token,
        uint128 _tokenAmount
    ) {
        require(
            _isPaymentAccepted(
                _tradeableCashflowAddress,
                _tradeableCashflowId,
                _erc20Token,
                _tokenAmount
            ),
            "Offer to be in specified ERC20/Eth"
        );
        _;
    }

    modifier isRequestOver(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) {
        require(
            !_isRequestOngoing(_tradeableCashflowAddress, _tradeableCashflowId),
            "Request is not yet over"
        );
        _;
    }

    modifier notZeroAddress(address _address) {
        require(_address != address(0), "Cannot specify 0 address");
        _;
    }

    modifier isFeePercentagesLessThanMaximum(uint32[] memory _feePercentages) {
        uint32 totalPercent;
        for (uint256 i = 0; i < _feePercentages.length; i++) {
            totalPercent = totalPercent + _feePercentages[i];
        }
        require(totalPercent <= 10000, "Fee percentages exceed maximum");
        _;
    }

    modifier correctFeeRecipientsAndPercentages(
        uint256 _recipientsLength,
        uint256 _percentagesLength
    ) {
        require(
            _recipientsLength == _percentagesLength,
            "Recipients != percentages"
        );
        _;
    }

    modifier isNotASale(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) {
        require(
            !_isASale(_tradeableCashflowAddress, _tradeableCashflowId),
            "Not applicable for a sale"
        );
        _;
    }

    /**********************************/
    /*╔═════════════════════════════╗
      ║             END             ║
      ║          MODIFIERS          ║
      ╚═════════════════════════════╝*/
    /**********************************/
    // constructor
    constructor() {
        defaultnewOfferPeriod = 86400; //1 day
    }

    /*╔══════════════════════════════╗
      ║    REQUEST CHECK FUNCTIONS   ║
      ╚══════════════════════════════╝*/
    function _isRequestOngoing(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal view returns (bool) {
        uint64 requestEndTimestamp = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].requestEnd;
        //if the requestEnd is set to 0, the auction is technically on-going, however
        //the maximum interest rate offer (maxInterestRAteOffer) has not yet been met.
        return (requestEndTimestamp == 0 ||
            block.timestamp < requestEndTimestamp);
    }

    /*
     * Check if an offer has been made. This is applicable in the early offer scenario
     * to ensure that if a request is created after an early offer, the request
     * begins appropriately or is settled if the instantAcceptableInterestRate is met.
     */
    function _isAnOfferMade(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal view returns (bool) {
        return (LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .lowestInterestRateOffered <=
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .maxInterestRate);
    }

    /*
     *if the maxInterestRate is set by the borrower, check that the lowest interest rate offered is met or is below that interest rate.
     */
    function _isMaximumInterestRateOffered(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal view returns (bool) {
        uint128 maxInterestRate = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].maxInterestRate;
        return
            maxInterestRate > 0 &&
            (LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .lowestInterestRateOffered <= maxInterestRate);
    }

    /*
     * If the instant acceptable interest rate is set by the borrower, check that the lowest interest rate offer meets that interest rate.
     */
    function _isInstantAcceptableInterestRateMet(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal view returns (bool) {
        uint128 instantAcceptableInterestRate = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].instantAcceptableInterestRate;
        return
            instantAcceptableInterestRate > 0 &&
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .lowestInterestRateOffered >=
            instantAcceptableInterestRate;
    }

    /*
     * Check that an offer is applicable, meeting request requirements.
     * In the case of direct loan: the offer needs to meet the instantAcceptableInterestRate.
     * In the case of a loan offer: the offer needs to be a % lower than the previous offer.
     */
    function _doesOfferMeetOfferRequirements(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        uint128 _tokenAmount,
        uint128 _offeredInterestRate
    ) internal view returns (bool) {
        uint128 loanAmount = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].loanAmount;

        if (msg.value < loanAmount && _tokenAmount < loanAmount) {
            return false;
        }

        uint128 instantAcceptableInterestRate = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].instantAcceptableInterestRate;
        //if instantAcceptableInterestRate is met, ignore increase percentage
        if (
            instantAcceptableInterestRate > 0 &&
            (_offeredInterestRate >= instantAcceptableInterestRate)
        ) {
            return true;
        }
        //if this is an offer for request, the offer needs to be a % lower than the previous interest rate Offered
        uint256 lowestInterestRateOffered = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].lowestInterestRateOffered;
        return (lowestInterestRateOffered >= 0 &&
            _offeredInterestRate >= 0 &&
            _offeredInterestRate < lowestInterestRateOffered);
    }

    /*
     * An NFT is up for sale if the instantAcceptableInterestRate is set, but the maxInterestRate is not set.
     * Therefore the only way to conclude the NFT sale is to meet the instantAcceptableInterestRate.
     */
    function _isASale(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal view returns (bool) {
        return (LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .instantAcceptableInterestRate >
            0 &&
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .maxInterestRate ==
            0);
    }

    function _isWhitelistedSale(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal view returns (bool) {
        return (LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .whitelistedLoaner != address(0));
    }

    /*
     * The best loaner is allowed to purchase the NFT if
     * no whitelistedloaner is set by the borrower.
     * Otherwise, the best loaner must equal the whitelisted loaner.
     */
    function _isBestLoanerAllowedToOffer(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal view returns (bool) {
        return
            (
                !_isWhitelistedSale(
                    _tradeableCashflowAddress,
                    _tradeableCashflowId
                )
            ) ||
            _isBestLoanerWhitelisted(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            );
    }

    function _isBestLoanerWhitelisted(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal view returns (bool) {
        return (LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .bestLoaner ==
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .whitelistedLoaner);
    }

    /**
     * Payment is accepted in the following scenarios:
     * (1) Auction already created - can accept ETH or Specified Token
     *  --------> Cannot offer with ETH & an ERC20 Token together in any circumstance<------
     * (2) Auction not created - only ETH accepted (cannot early offer with an ERC20 Token
     * (3) Cannot make a zero offer (no ETH or Token amount)
     */
    function _isPaymentAccepted(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _OfferERC20Token,
        uint128 _tokenAmount
    ) internal view returns (bool) {
        address auctionERC20Token = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].ERC20Token;
        if (_isERC20Auction(auctionERC20Token)) {
            return
                msg.value == 0 &&
                auctionERC20Token == _OfferERC20Token &&
                _tokenAmount > 0;
        } else {
            return
                msg.value != 0 &&
                _OfferERC20Token == address(0) &&
                _tokenAmount == 0;
        }
    }

    function _isERC20Auction(address _auctionERC20Token)
        internal
        pure
        returns (bool)
    {
        return _auctionERC20Token != address(0);
    }

    /*
     * Returns the percentage of the total Offer (used to calculate fee payments)
     */
    function _getPortionOfOffer(uint256 _totalOffer, uint256 _percentage)
        internal
        pure
        returns (uint256)
    {
        return (_totalOffer * (_percentage)) / 10000;
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║    AUCTION CHECK FUNCTIONS   ║
      ╚══════════════════════════════╝*/
    /**********************************/
    /*╔══════════════════════════════╗
      ║    DEFAULT GETTER FUNCTIONS  ║
      ╚══════════════════════════════╝*/
    /*****************************************************************
     * These functions check if the applicable auction parameter has *
     * been set by the Borrower. If not, return the default value. *
     *****************************************************************/

    function _getnewOfferPeriod(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal view returns (uint32) {
        uint32 newOfferPeriod = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].newOfferPeriod;

        if (newOfferPeriod == 0) {
            return defaultnewOfferPeriod;
        } else {
            return newOfferPeriod;
        }
    }

    /*
     * The default value for the payment recipient is de lowest interest rate offerer (best loaner)
     */
    function _getpaymentRecipient(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal view returns (address) {
        address paymentRecipient = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].paymentRecipient;

        if (paymentRecipient == address(0)) {
            return
                LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                    .bestLoaner;
        } else {
            return paymentRecipient;
        }
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║    DEFAULT GETTER FUNCTIONS  ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║  TRANSFER NFTS TO CONTRACT   ║
      ╚══════════════════════════════╝*/
    function _transferTradeableCashflowToAuctionContract(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal {
        address _borrower = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].borrower;
        if (
            IERC721(_tradeableCashflowAddress).ownerOf(_tradeableCashflowId) ==
            _borrower
        ) {
            IERC721(_tradeableCashflowAddress).transferFrom(
                _borrower,
                address(this),
                _tradeableCashflowId
            );
            require(
                IERC721(_tradeableCashflowAddress).ownerOf(
                    _tradeableCashflowId
                ) == address(this),
                "nft transfer failed"
            );
        } else {
            require(
                IERC721(_tradeableCashflowAddress).ownerOf(
                    _tradeableCashflowId
                ) == address(this),
                "Borrower does not own tradeable cashflow"
            );
        }
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║  TRANSFER NFTS TO CONTRACT   ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║       AUCTION CREATION       ║
      ╚══════════════════════════════╝*/

    /**
     * Setup parameters applicable to all auctions and whitelised sales:
     * -> ERC20 Token for payment (if specified by the borrower) : _erc20Token
     * -> minimum price : _maxInterestRate
     * -> instant acceptable interest rate: _instantAcceptableInterestRate
     * -> the borrower: msg.sender
     * -> The fee recipients & their respective percentages for a sucessful request/loan
     */
    function _setupAuction(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _erc20Token,
        uint128 _maxInterestRate,
        uint128 _instantAcceptableInterestRate,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        internal
        correctFeeRecipientsAndPercentages(
            _feeRecipients.length,
            _feePercentages.length
        )
        isFeePercentagesLessThanMaximum(_feePercentages)
    {
        if (_erc20Token != address(0)) {
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .ERC20Token = _erc20Token;
        }
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .feeRecipients = _feeRecipients;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .feePercentages = _feePercentages;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .instantAcceptableInterestRate = _instantAcceptableInterestRate;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .maxInterestRate = _maxInterestRate;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .borrower = msg.sender;
    }

    function _createNewNftAuction(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _erc20Token,
        uint128 _maxInterestRate,
        uint128 _instantAcceptableInterestRate,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    ) internal {
        // Sending the NFT to this contract
        _setupAuction(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _erc20Token,
            _maxInterestRate,
            _instantAcceptableInterestRate,
            _feeRecipients,
            _feePercentages
        );
        emit RequestCreated(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            msg.sender,
            _erc20Token,
            _maxInterestRate,
            _instantAcceptableInterestRate,
            _getnewOfferPeriod(_tradeableCashflowAddress, _tradeableCashflowId),
            _feeRecipients,
            _feePercentages
        );
        _updateOngoingAuction(_tradeableCashflowAddress, _tradeableCashflowId);
    }

    /**
     * Create an auction that uses the default Offer increase percentage
     * & the default auction Offer period.
     */
    function createDefaultNftAuction(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _erc20Token,
        uint128 _maxInterestRate,
        uint128 _instantAcceptableInterestRate,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        external
        isRequestNotStartedByOwner(
            _tradeableCashflowAddress,
            _tradeableCashflowId
        )
        borrowAmountGreaterThanZero(_maxInterestRate)
    {
        _createNewNftAuction(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _erc20Token,
            _maxInterestRate,
            _instantAcceptableInterestRate,
            _feeRecipients,
            _feePercentages
        );
    }

    function createNewRequest(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _erc20Token,
        uint128 _maxInterestRate,
        uint128 _instantAcceptableInterestRate,
        uint32 _newOfferPeriod, //this is the time that the auction lasts until another Offer occurs
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        external
        isRequestNotStartedByOwner(
            _tradeableCashflowAddress,
            _tradeableCashflowId
        )
        borrowAmountGreaterThanZero(_maxInterestRate)
    {
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .newOfferPeriod = _newOfferPeriod;
        _createNewNftAuction(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _erc20Token,
            _maxInterestRate,
            _instantAcceptableInterestRate,
            _feeRecipients,
            _feePercentages
        );
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║       AUCTION CREATION       ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║            SALES             ║
      ╚══════════════════════════════╝*/

    /********************************************************************
     * Allows for a standard sale mechanism where the borrower can    *
     * can select an address to be whitelisted. This address is then    *
     * allowed to make a Offer on the NFT. No other address can Offer on    *
     * the NFT.                                                         *
     ********************************************************************/
    function _setupSale(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _erc20Token,
        uint128 _instantAcceptableInterestRate,
        address _whitelistedLoaner,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        internal
        correctFeeRecipientsAndPercentages(
            _feeRecipients.length,
            _feePercentages.length
        )
        isFeePercentagesLessThanMaximum(_feePercentages)
    {
        if (_erc20Token != address(0)) {
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .ERC20Token = _erc20Token;
        }
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .feeRecipients = _feeRecipients;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .feePercentages = _feePercentages;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .instantAcceptableInterestRate = _instantAcceptableInterestRate;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .whitelistedLoaner = _whitelistedLoaner;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .borrower = msg.sender;
    }

    function createSale(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _erc20Token,
        uint128 _instantAcceptableInterestRate,
        address _whitelistedLoaner,
        address[] memory _feeRecipients,
        uint32[] memory _feePercentages
    )
        external
        isRequestNotStartedByOwner(
            _tradeableCashflowAddress,
            _tradeableCashflowId
        )
        borrowAmountGreaterThanZero(_instantAcceptableInterestRate)
    {
        //min price = 0
        _setupSale(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _erc20Token,
            _instantAcceptableInterestRate,
            _whitelistedLoaner,
            _feeRecipients,
            _feePercentages
        );

        emit OfferAccepted(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            msg.sender,
            _erc20Token,
            _instantAcceptableInterestRate,
            _whitelistedLoaner,
            _feeRecipients,
            _feePercentages
        );
        //check if instantAcceptableInterestRate is meet and conclude sale, otherwise reverse the early Offer
        if (_isAnOfferMade(_tradeableCashflowAddress, _tradeableCashflowId)) {
            if (
                //we only revert the underOffer if the borrower specifies a different
                //whitelisted loaner to the best loaner
                _isBestLoanerAllowedToOffer(
                    _tradeableCashflowAddress,
                    _tradeableCashflowId
                )
            ) {
                if (
                    _isInstantAcceptableInterestRateMet(
                        _tradeableCashflowAddress,
                        _tradeableCashflowId
                    )
                ) {
                    _transferTradeableCashflowToAuctionContract(
                        _tradeableCashflowAddress,
                        _tradeableCashflowId
                    );
                    _transferTradeableCashflowAndPayBorrower(
                        _tradeableCashflowAddress,
                        _tradeableCashflowId
                    );
                }
            } else {
                _reverseAndResetPreviousOffer(
                    _tradeableCashflowAddress,
                    _tradeableCashflowId
                );
            }
        }
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║            SALES             ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔═════════════════════════════╗
      ║        Offer FUNCTIONS        ║
      ╚═════════════════════════════╝*/

    /********************************************************************
     * Make Offers with ETH or an ERC20 Token specified by the borrower.*
     * Additionally, a loaner can offer the asking interest rate        *
     * to conclude a request.                                           *                                                         *
     ********************************************************************/

    function _makeOffer(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _erc20Token,
        uint128 _tokenAmount,
        uint128 _offeredInterestRate
    )
        internal
        notBorrower(_tradeableCashflowAddress, _tradeableCashflowId)
        paymentAccepted(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _erc20Token,
            _tokenAmount
        )
        offerAmountMeetsOfferRequirements(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _tokenAmount,
            _offeredInterestRate
        )
    {
        _reversePreviousOfferAndUpdateLowestInterestRateOffered(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _tokenAmount
        );
        emit OfferMade(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            msg.sender,
            msg.value,
            _erc20Token,
            _tokenAmount
        );
        _updateOngoingAuction(_tradeableCashflowAddress, _tradeableCashflowId);
    }

    function makeOffer(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _erc20Token,
        uint128 _tokenAmount,
        uint128 _offeredInterestRate
    )
        external
        payable
        requestOngoing(_tradeableCashflowAddress, _tradeableCashflowId)
        onlyApplicableLoaner(_tradeableCashflowAddress, _tradeableCashflowId)
    {
        _makeOffer(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _erc20Token,
            _tokenAmount,
            _offeredInterestRate
        );
    }

    function makeCustomOffer(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _erc20Token,
        uint128 _tokenAmount,
        address _paymentRecipient,
        uint128 _offeredInterestRate
    )
        external
        payable
        requestOngoing(_tradeableCashflowAddress, _tradeableCashflowId)
        notZeroAddress(_paymentRecipient)
        onlyApplicableLoaner(_tradeableCashflowAddress, _tradeableCashflowId)
    {
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .paymentRecipient = _paymentRecipient;
        _makeOffer(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _erc20Token,
            _tokenAmount,
            _offeredInterestRate
        );
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║        Offer FUNCTIONS         ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║       UPDATE AUCTION         ║
      ╚══════════════════════════════╝*/

    /***************************************************************
     * Settle an auction or sale if the instantAcceptableInterestRate is met or set  *
     *  auction period to begin if the minimum price has been met. *
     ***************************************************************/
    function _updateOngoingAuction(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal {
        if (
            _isInstantAcceptableInterestRateMet(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            )
        ) {
            _transferTradeableCashflowToAuctionContract(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            );
            _transferTradeableCashflowAndPayBorrower(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            );
            return;
        }
        //min price not set, nft not up for auction yet
        if (
            _isMaximumInterestRateOffered(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            )
        ) {
            _transferTradeableCashflowToAuctionContract(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            );
            _updaterequestEnd(_tradeableCashflowAddress, _tradeableCashflowId);
        }
    }

    function _updaterequestEnd(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal {
        //the auction end is always set to now + the Offer period
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .requestEnd =
            _getnewOfferPeriod(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            ) +
            uint64(block.timestamp);
        emit RequestPeriodUpdated(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .requestEnd
        );
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║       UPDATE AUCTION         ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║       RESET FUNCTIONS        ║
      ╚══════════════════════════════╝*/

    /*
     * Reset all auction related parameters for an NFT.
     * This effectively removes a Request from loan market
     */
    function _resetRequest(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal {
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .maxInterestRate = 0;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .instantAcceptableInterestRate = 0;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .requestEnd = 0;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .newOfferPeriod = 0;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .borrower = address(0);
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .whitelistedLoaner = address(0);
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .ERC20Token = address(0);
    }

    /*
     * Reset all offers related parameters for a Request.
     * This effectively sets a Request as having no active offers
     */
    function _resetOffers(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal {
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .bestLoaner = address(0);
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .lowestInterestRateOffered = 0;
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .paymentRecipient = address(0);
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║       RESET FUNCTIONS        ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║         UPDATE OfferS          ║
      ╚══════════════════════════════╝*/
    /******************************************************************
     * Internal functions that update Offer parameters and reverse Offers *
     * to ensure contract only holds the lowest interest rate offer.                 *
     ******************************************************************/
    function _updateLowestInterestRateOffered(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        uint128 _tokenAmount
    ) internal {
        address auctionERC20Token = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].ERC20Token;
        if (_isERC20Auction(auctionERC20Token)) {
            IERC20(auctionERC20Token).transferFrom(
                msg.sender,
                address(this),
                _tokenAmount
            );
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .lowestInterestRateOffered = _tokenAmount;
        } else {
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .lowestInterestRateOffered = uint128(msg.value);
        }
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .bestLoaner = msg.sender;
    }

    function _reverseAndResetPreviousOffer(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal {
        address lowestInterestRateOfferedder = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].bestLoaner;

        uint128 lowestInterestRateOffered = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].lowestInterestRateOffered;
        _resetOffers(_tradeableCashflowAddress, _tradeableCashflowId);

        _payout(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            lowestInterestRateOfferedder,
            lowestInterestRateOffered
        );
    }

    function _reversePreviousOfferAndUpdateLowestInterestRateOffered(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        uint128 _tokenAmount
    ) internal {
        address prevlowestInterestRateOfferedder = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].bestLoaner;

        uint256 prevlowestInterestRateOffered = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].lowestInterestRateOffered;
        _updateLowestInterestRateOffered(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _tokenAmount
        );

        if (prevlowestInterestRateOfferedder != address(0)) {
            _payout(
                _tradeableCashflowAddress,
                _tradeableCashflowId,
                prevlowestInterestRateOfferedder,
                prevlowestInterestRateOffered
            );
        }
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║         UPDATE OfferS          ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║  TRANSFER NFT & PAY Borrower ║
      ╚══════════════════════════════╝*/
    function _transferTradeableCashflowAndPayBorrower(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) internal {
        address _borrower = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].borrower;
        address _lowestInterestRateOfferedder = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].bestLoaner;
        address _paymentRecipient = _getpaymentRecipient(
            _tradeableCashflowAddress,
            _tradeableCashflowId
        );
        uint128 _lowestInterestRateOffered = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].lowestInterestRateOffered;
        _resetOffers(_tradeableCashflowAddress, _tradeableCashflowId);

        _payFeesAndBorrower(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _borrower,
            _lowestInterestRateOffered
        );
        IERC721(_tradeableCashflowAddress).transferFrom(
            address(this),
            _paymentRecipient,
            _tradeableCashflowId
        );

        _resetRequest(_tradeableCashflowAddress, _tradeableCashflowId);
        emit TradeableCashTransferedAndLoanerPaid(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _borrower,
            _lowestInterestRateOffered,
            _lowestInterestRateOfferedder,
            _paymentRecipient
        );
    }

    function _payFeesAndBorrower(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _borrower,
        uint256 _lowestInterestRateOffered
    ) internal {
        uint256 feesPaid;
        for (
            uint256 i = 0;
            i <
            LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                .feeRecipients
                .length;
            i++
        ) {
            uint256 fee = _getPortionOfOffer(
                _lowestInterestRateOffered,
                LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                    .feePercentages[i]
            );
            feesPaid = feesPaid + fee;
            _payout(
                _tradeableCashflowAddress,
                _tradeableCashflowId,
                LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
                    .feeRecipients[i],
                fee
            );
        }
        _payout(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _borrower,
            (_lowestInterestRateOffered - feesPaid)
        );
    }

    function _payout(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _recipient,
        uint256 _amount
    ) internal {
        address auctionERC20Token = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].ERC20Token;
        if (_isERC20Auction(auctionERC20Token)) {
            IERC20(auctionERC20Token).transfer(_recipient, _amount);
        } else {
            // attempt to send the funds to the recipient
            (bool success, ) = payable(_recipient).call{
                value: _amount,
                gas: 20000
            }("");
            // if it failed, update their credit balance so they can pull it later
            if (!success) {
                failedTransferCredits[_recipient] =
                    failedTransferCredits[_recipient] +
                    _amount;
            }
        }
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║  TRANSFER NFT & PAY Borrower ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║      SETTLE & WITHDRAW       ║
      ╚══════════════════════════════╝*/
    function settleRequest(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) external isRequestOver(_tradeableCashflowAddress, _tradeableCashflowId) {
        _transferTradeableCashflowAndPayBorrower(
            _tradeableCashflowAddress,
            _tradeableCashflowId
        );
        emit RequestSettled(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            msg.sender
        );
    }

    function withdrawAuction(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) external {
        //only the NFT owner can prematurely close and auction
        require(
            IERC721(_tradeableCashflowAddress).ownerOf(_tradeableCashflowId) ==
                msg.sender,
            "Not NFT owner"
        );
        _resetRequest(_tradeableCashflowAddress, _tradeableCashflowId);
        emit RequestWithdrawn(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            msg.sender
        );
    }

    function withdrawOffer(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    )
        external
        maximumInteresRateOffered(
            _tradeableCashflowAddress,
            _tradeableCashflowId
        )
    {
        address lowestInterestRateOfferedder = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].bestLoaner;
        require(
            msg.sender == lowestInterestRateOfferedder,
            "Cannot withdraw funds"
        );

        uint128 lowestInterestRateOffered = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].lowestInterestRateOffered;
        _resetOffers(_tradeableCashflowAddress, _tradeableCashflowId);

        _payout(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            lowestInterestRateOfferedder,
            lowestInterestRateOffered
        );

        emit OfferWithdrawn(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            msg.sender
        );
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║      SETTLE & WITHDRAW       ║
      ╚══════════════════════════════╝*/
    /**********************************/

    /*╔══════════════════════════════╗
      ║       UPDATE AUCTION         ║
      ╚══════════════════════════════╝*/
    function updatewhitelistedLoaner(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        address _newwhitelistedLoaner
    ) external onlyBorrower(_tradeableCashflowAddress, _tradeableCashflowId) {
        require(
            _isASale(_tradeableCashflowAddress, _tradeableCashflowId),
            "Not a sale"
        );
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .whitelistedLoaner = _newwhitelistedLoaner;
        //if an underoffer is by a non whitelisted laoner,reverse that offer
        address lowestInterestRateOfferedder = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].bestLoaner;
        uint128 lowestInterestRateOffered = LoanRequests[
            _tradeableCashflowAddress
        ][_tradeableCashflowId].lowestInterestRateOffered;
        if (
            lowestInterestRateOffered > 0 &&
            !(lowestInterestRateOfferedder == _newwhitelistedLoaner)
        ) {
            //we only revert the underoffer if the borrower specifies a different
            //whitelisted loaner to the best loaner

            _resetOffers(_tradeableCashflowAddress, _tradeableCashflowId);

            _payout(
                _tradeableCashflowAddress,
                _tradeableCashflowId,
                lowestInterestRateOfferedder,
                lowestInterestRateOffered
            );
        }

        emit WhitelistedLoanerUpdated(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _newwhitelistedLoaner
        );
    }

    function updateMinimumPrice(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        uint128 _newmaxInterestRate
    )
        external
        onlyBorrower(_tradeableCashflowAddress, _tradeableCashflowId)
        maximumInteresRateOffered(
            _tradeableCashflowAddress,
            _tradeableCashflowId
        )
        isNotASale(_tradeableCashflowAddress, _tradeableCashflowId)
        borrowAmountGreaterThanZero(_newmaxInterestRate)
    {
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .maxInterestRate = _newmaxInterestRate;

        emit MaxInterestRateUpdated(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _newmaxInterestRate
        );

        if (
            _isMaximumInterestRateOffered(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            )
        ) {
            _transferTradeableCashflowToAuctionContract(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            );
            _updaterequestEnd(_tradeableCashflowAddress, _tradeableCashflowId);
        }
    }

    function updateinstantAcceptableInterestRate(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId,
        uint128 _newinstantAcceptableInterestRate
    )
        external
        onlyBorrower(_tradeableCashflowAddress, _tradeableCashflowId)
        borrowAmountGreaterThanZero(_newinstantAcceptableInterestRate)
    {
        LoanRequests[_tradeableCashflowAddress][_tradeableCashflowId]
            .instantAcceptableInterestRate = _newinstantAcceptableInterestRate;
        emit instantAcceptableInterestRateUpdated(
            _tradeableCashflowAddress,
            _tradeableCashflowId,
            _newinstantAcceptableInterestRate
        );
        if (
            _isInstantAcceptableInterestRateMet(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            )
        ) {
            _transferTradeableCashflowToAuctionContract(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            );
            _transferTradeableCashflowAndPayBorrower(
                _tradeableCashflowAddress,
                _tradeableCashflowId
            );
        }
    }

    /*
     * The Borrower can opt to end a request by taking the current lowest interest rate.
     */
    function takeLowestInterestRate(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) external onlyBorrower(_tradeableCashflowAddress, _tradeableCashflowId) {
        require(
            _isAnOfferMade(_tradeableCashflowAddress, _tradeableCashflowId),
            "cannot payout 0 offer"
        );
        _transferTradeableCashflowToAuctionContract(
            _tradeableCashflowAddress,
            _tradeableCashflowId
        );
        _transferTradeableCashflowAndPayBorrower(
            _tradeableCashflowAddress,
            _tradeableCashflowId
        );
        emit LowestInterestRateTaken(
            _tradeableCashflowAddress,
            _tradeableCashflowId
        );
    }

    /*
     * Query the owner of a request accepting offers
     */
    function borrower(
        address _tradeableCashflowAddress,
        uint256 _tradeableCashflowId
    ) external view returns (address) {
        address _borrower = LoanRequests[_tradeableCashflowAddress][
            _tradeableCashflowId
        ].borrower;
        require(_borrower != address(0), "TradeableCashflow not deposited");

        return _borrower;
    }

    /*
     * If the transfer of an offer has failed, allow the recipient to reclaim their amount later.
     */
    function withdrawAllFailedCredits() external {
        uint256 amount = failedTransferCredits[msg.sender];

        require(amount != 0, "no credits to withdraw");

        failedTransferCredits[msg.sender] = 0;

        (bool successfulWithdraw, ) = msg.sender.call{
            value: amount,
            gas: 20000
        }("");
        require(successfulWithdraw, "withdraw failed");
    }

    /**********************************/
    /*╔══════════════════════════════╗
      ║             END              ║
      ║       UPDATE AUCTION         ║
      ╚══════════════════════════════╝*/
    /**********************************/
}
