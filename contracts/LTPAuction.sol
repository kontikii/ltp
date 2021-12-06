// SPDX-License-Identifier: GPL-3.0

/// @title LTP auction house (you're the one making this weird)


// LICENSE
//
// LTPAuction.sol is a modified version of DogsAuctionHouse.sol:
// https://github.com/markcarey/degendogs/blob/bc626b8765bb38ddb61f4bf2a2459ba6699bcc9f/contracts/DogsAuctionHouse.sol
// 
// DogsAuctionHouse.sol is a modified version of Nounders DAO's NounsAuctionHouse.sol:
// https://github.com/nounsDAO/nouns-monorepo/blob/8f614378f93c1f6fec35a254eb424f70e84925dd/packages/nouns-contracts/contracts/NounsAuctionHouse.sol
//
// NounsAuctionHouse.sol is a modified version of Zora's AuctionHouse.sol:
// https://github.com/ourzora/auction-house/blob/54a12ec1a6cf562e49f0a4917990474b11350a2d/contracts/AuctionHouse.sol
//
// AuctionHouse.sol source code Copyright Zora licensed under the GPL-3.0 license.
// With modifications by Nounders DAO and Degen Dogs Club.

pragma solidity ^0.8.0;

import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import { ReentrancyGuardUpgradeable } from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { ILTPAuction } from './interfaces/ILTPAuction.sol';
import { ILongTermPeople } from './interfaces/ILongTermPeople.sol';
import { IWETH } from './interfaces/IWETH.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract LTPAuction is ILTPAuction, PausableUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    // The LongTermPeeps ERC721 token contract
    ILongTermPeople public peeps;

    // The address of the WETH contract
    address public weth;

    // The minimum amount of time left in an auction after a new bid is created
    uint256 public timeBuffer;

    // The minimum price accepted in an auction
    uint256 public reservePrice;

    // The minimum percentage difference between the last bid amount and the current bid
    uint8 public minBidIncrementPercentage;

    // The duration of a single auction
    uint256 public duration;

    // The active auction
    ILTPAuction.Auction public auction;

    /**
     * @notice Initialize the auction house and base contracts,
     * populate configuration values, and pause the contract.
     * @dev This function can only be called once.
     */

    function initialize ( 
        ILongTermPeople _peeps,
        address _weth,
        uint256 _timeBuffer,
        uint256 _reservePrice,
        uint8 _minBidIncrementPercentage,
        uint256 _duration
    ) external initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __Ownable_init();

        _pause();

        peeps = _peeps;
        weth = _weth;
        timeBuffer = _timeBuffer;
        reservePrice = _reservePrice;
        minBidIncrementPercentage = _minBidIncrementPercentage;
        duration = _duration;
    }

    function paymegas() public payable {

    }

    /**
     * @notice Settle the current auction, mint a new Dog, and put it up for auction.
     */
    function settleCurrentAndCreateNewAuction() external override nonReentrant whenNotPaused  {
        _settleAuction();
        _createAuction();
    }

    /**
     * @notice Settle the current auction.
     * @dev This function can only be called when the contract is paused.
     */
    function settleAuction() external override whenPaused nonReentrant {
        _settleAuction();
    }

    // testing mostly baby :)
    function createAuction() external onlyOwner {
        _createAuction();
    }

    /**
     * @notice Create a bid for a Peep, with a given amount.
     * @dev This contract only accepts payment in ETH. 
     */
    function createBid(uint256 peepId, string memory tokenURI) external payable override nonReentrant {
        ILTPAuction.Auction memory _auction = auction;
        
        require(_auction.peepId == peepId, 'Peep not up for auction');
        require(block.timestamp < _auction.endTime, 'Auction expired');
        require(msg.value >= reservePrice, 'Must send at least reservePrice');
        require(
            msg.value >= _auction.amount + ((_auction.amount * minBidIncrementPercentage) / 100),
            'Must send more than last bid by minBidIncrementPercentage amount'
        );

        address payable lastBidder = _auction.bidder; // queriable bids? or just huge bloated contract. get indexing man

        // Refund the last bidder, if applicable
        if (lastBidder != address(0)) {
            _safeTransferETHWithFallback(lastBidder, _auction.amount);
        }

        auction.amount = msg.value;
        auction.bidder = payable(msg.sender);
        auction.bidTokenURI = tokenURI;

        // Extend the auction if the bid was received within `timeBuffer` of the auction end time
        bool extended = _auction.endTime - block.timestamp < timeBuffer;
        if (extended) {
            auction.endTime = _auction.endTime = block.timestamp + timeBuffer;
        }

        emit AuctionBid(_auction.peepId, msg.sender, tokenURI, msg.value, extended);

        if (extended) {
            emit AuctionExtended(_auction.peepId, _auction.endTime);
        }
    }

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();

        if (auction.startTime == 0 || auction.settled) {
            _createAuction();
        }
    }

    /**
     * @notice Create an auction.
     * @dev Store the auction details in the `auction` state variable and emit an AuctionCreated event.
     * If the mint reverts, the minter was updated without pausing this contract first. To remedy this,
     * catch the revert and pause this contract. 
     * edit: trying without the pausing/unpausing functionality currently.
     */
    function _createAuction() internal {

        try peeps.mint() returns (uint256 peepId) {
            uint256 startTime = block.timestamp;
            uint256 endTime = startTime + duration;

            auction = Auction({
                peepId: peepId,
                amount: 0,
                startTime: startTime,
                endTime: endTime,
                bidder: payable(0),
                bidTokenURI: "",
                settled: false
            });

            emit AuctionCreated(peepId, startTime, endTime);
        } catch Error(string memory) {
            _pause();
        }
    }


    /**
     * @notice Settle an auction, finalizing the bid and paying out to the owner.
     * @dev If there are no bids, the Person is BRUTALLU incenerated.
     */
    function _settleAuction() internal {
        ILTPAuction.Auction memory _auction = auction;

        require(_auction.startTime != 0, "Auction hasn't begun");
        require(!_auction.settled, 'Auction has already been settled');
        require(block.timestamp >= _auction.endTime, "Auction hasn't completed");

        auction.settled = true;

        if (_auction.bidder == address(0)) {
            peeps.burnNft(); // add id & event for this häppening
        } else {
            peeps.issueNft{value: _auction.amount}(_auction.bidder, _auction.peepId, _auction.amount, _auction.bidTokenURI);
        }

        emit AuctionSettled(_auction.peepId, _auction.bidder, _auction.amount);

    }

    /**
     * @notice Set the auction time buffer.
     * @dev Only callable by the owner.
     */
    function setTimeBuffer(uint256 _timeBuffer) external override onlyOwner {
        timeBuffer = _timeBuffer;

        emit AuctionTimeBufferUpdated(_timeBuffer);
    }

    /**
     * @notice Set the auction reserve price.
     * @dev Only callable by the owner.
     */
    function setReservePrice(uint256 _reservePrice) external override onlyOwner {
        reservePrice = _reservePrice;

        emit AuctionReservePriceUpdated(_reservePrice);
    }

    /**
     * @notice Set the auction minimum bid increment percentage.
     * @dev Only callable by the owner.
     */
    function setMinBidIncrementPercentage(uint8 _minBidIncrementPercentage) external override onlyOwner {
        minBidIncrementPercentage = _minBidIncrementPercentage;

        emit AuctionMinBidIncrementPercentageUpdated(_minBidIncrementPercentage);
    }

    /**
     * @notice Transfer ETH. If the ETH transfer fails, wrap the ETH and try send it as WETH.
     */
    function _safeTransferETHWithFallback(address to, uint256 amount) internal {
        if (!_safeTransferETH(to, amount)) {
            IWETH(weth).deposit{ value: amount }();
            IERC20(weth).transfer(to, amount);
        }
    }

    /**
     * @notice Transfer ETH and return the success status.
     * @dev This function only forwards 30,000 gas to the callee.
     */
    function _safeTransferETH(address to, uint256 value) internal returns (bool) {
        (bool success, ) = to.call{ value: value, gas: 30_000 }(new bytes(0));
        return success;
    }
}