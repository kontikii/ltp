pragma solidity ^0.8.0;

interface ILTPAuction {

    struct Auction {
        // ID for the peep (ERC721 token ID)
        uint256 peepId;
        // The current highest bid amount
        uint256 amount;
        // The time that the auction started
        uint256 startTime;
        // The time that the auction is scheduled to end
        uint256 endTime;
        // The address of the current highest bid
        // Note, how do we store/fetch the previous bids? Are they stored inherently? Or should we use a mapping?
        // events seems like a way to do it
        address payable bidder;
        // preffered ipfs hash of highest bidder
        string bidTokenURI;
        // Whether or not the auction has been settled
        bool settled;
    }

    event AuctionCreated(uint256 indexed peepId, uint256 startTime, uint256 endTime);

    event AuctionBid(uint256 indexed peepId, address sender, string tokenURI, uint256 value, bool extended);

    event AuctionExtended(uint256 indexed peepId, uint256 endTime);

    event AuctionSettled(uint256 indexed peepId, address winner, uint256 amount);

    event AuctionTimeBufferUpdated(uint256 timeBuffer);

    event AuctionReservePriceUpdated(uint256 reservePrice);

    event AuctionMinBidIncrementPercentageUpdated(uint256 minBidIncrementPercentage);

    function settleAuction() external;

    function settleCurrentAndCreateNewAuction() external;

    function createBid(uint256 peepId, string memory tokenURI) external payable;

    function pause() external;

    function unpause() external;

    function setTimeBuffer(uint256 timeBuffer) external;

    function setReservePrice(uint256 reservePrice) external;

    function setMinBidIncrementPercentage(uint8 minBidIncrementPercentage) external;

}