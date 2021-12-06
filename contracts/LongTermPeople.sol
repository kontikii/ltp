// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721URIStorage, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import {
    ISuperfluid,
    ISuperToken,
    SuperAppBase,
    SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";

import {
    IConstantFlowAgreementV1
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";


/**
  hey... damn this is cool. But really hard at the same time.
  love it :)
 */

contract LTP is
    Ownable,
    ERC721URIStorage,
    SuperAppBase
{

    ISuperToken private _acceptedToken;
    ISuperfluid private _host;
    IConstantFlowAgreementV1 private _cfa;

    address public minter; // contract (auctionHouse) with the permission to mint.
    
    struct Flow {
        uint256 tokenId;
        uint256 timestamp;
        int96 flowRate;
    }
    mapping(uint256 => Flow) private tokenFlows; // array of Flows possible
    
    mapping(uint256 => int96) private flowRates; // Q: uint vs int in this case?
    uint256 public nextId; // maybe replace by Counters.Counter?
    int96 private _testFlowRate;

    modifier onlyMinter() {
        require(msg.sender == minter, 'Sender is not the minter');
        _;
    }
    modifier onlyMinterOrOwner() {
        require( (msg.sender == minter) || (msg.sender == owner()), 'Sender is not the minter nor owner');
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        ISuperfluid host,
        IConstantFlowAgreementV1 cfa,
        ISuperToken acceptedToken
        )
        ERC721(name, symbol)
    {
        _acceptedToken = acceptedToken;
        _host = host;
        _cfa = cfa;
        
        nextId = 0;
        _testFlowRate = 10000; // 0.00001 weth/token per month

        uint256 configWord =
            SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP ;
        _host.registerApp(configWord);
    }
    
    // mints to own contract, but returns tokenId so auction can keep track
    function mint() external onlyMinterOrOwner returns (uint256) {
        _mint(address(this), nextId);
        flowRates[nextId] = _testFlowRate;

        uint256 ltpId = nextId;
        nextId += 1;
        return ltpId;
    }

    event NFTIssued(uint256 indexed tokenId, address indexed owner, string indexed tokenURI);

    // who won the auction for which nft, with what tokenURI comes from auction contract. Upon settlement this is called
    function issueNft(address to, uint256 tokenId, uint256 amount, string memory tokenURI) external payable onlyMinterOrOwner { 
        // Flow memory newFlow = new Flow(nextId, now, _testFlowRate); // save the default testing flow to tokenId
        require(to != address(this), "Issue to a new address");
        require(ownerOf(tokenId) == address(this), "NFT already issued");
        
        // save winning bid too?

        _setTokenURI(tokenId, tokenURI);
        this.safeTransferFrom(address(this), to, tokenId);
        emit NFTIssued(tokenId, to, tokenURI);
    }

    function burnNft() external onlyMinterOrOwner { // if auction doesn't settle ?
        _mint(address(0), nextId);
        nextId += 1;
    }


    // AHHHHH why the fucking exception in issue...
    function setTokenURI(uint256 tokenId, string memory tokenURI) public {
        _setTokenURI(tokenId, tokenURI);
    }

    function transferToMe(uint256 tokenId) public {
        this.safeTransferFrom(address(this), msg.sender, tokenId);
    }


    function getNextId() external view returns (uint256) {
        return nextId;
    }

    function _beforeTokenTransfer( // TODO, add more mature flow redirection systems
        address from, 
        address to, 
        uint256 tokenId
        ) internal override {
        // should maybe block superapps from getting these?

        // if its a mint then no reduction necessary 
        if (from == address(0)) {

        } else if (from == address(this)) {
            _increaseFlow(to, flowRates[tokenId]);
        } else {
          _deleteFlow(address(this), from);
          _increaseFlow(to, flowRates[tokenId]);
        }   
    }

    function _reduceFlow(address from, int96 flowRate) internal {
        // currently using _deleteFlow for this, updateFlow is another way of accomplishing reduction
    }

    function _increaseFlow(address to, int96 flowRate) internal {
        //(, int96 outFlowRate, , ) = _cfa.getFlow(_acceptedToken, address(this), to);
        _createFlow(to, flowRate);

        // if (outFlowRate == 0) {
        //     _createFlow(to, flowRate);
        // }
    }

    function _createFlow(address to, int96 flowRate) internal {
        // include checks of streaming to yourself
        _host.callAgreement(
            _cfa, 
            abi.encodeWithSelector(
            _cfa.createFlow.selector, 
            _acceptedToken,
            to,
            flowRate,
            new bytes(0) // placeholder
            ), 
        "0x0"
        );
    }

    function _updateFlow(address to, int96 flowRate) internal {
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.updateFlow.selector,
                _acceptedToken,
                to,
                flowRate,
                new bytes(0) // placeholder
            ),
            "0x"
        );
    }
    
    function _deleteFlow(address from, address to) internal {
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.deleteFlow.selector,
                _acceptedToken,
                from,
                to,
                new bytes(0) // placeholder
            ),
            "0x"
        );
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    } 
    
    function setFlowRate(int96 flowRate) external onlyOwner returns (int96 newFlowRate) {
        _testFlowRate = flowRate;
        return flowRate;
    }

    // temp functions for testing purposes
    function withdrawETH() external payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
    function paymegas() external payable {
        
    }

    //  superapp callbacks

    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata /*_agreementData*/,
        bytes calldata ,// _cbdata,
        bytes calldata _ctx
    )
        external override
        returns (bytes memory newCtx)
    {
        return _updateOutflow(_ctx);
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata agreementData,
        bytes calldata ,//_cbdata,
        bytes calldata _ctx
    )
        external override
        returns (bytes memory newCtx)
    {
        return _updateOutflow(_ctx);
    }

    /// @dev If a new stream is opened, or an existing one is opened
    function _updateOutflow(bytes calldata ctx) 
        private
        returns (bytes memory newCtx) 
    {
        newCtx = ctx;
        
        int96 netFlowRate = _cfa.getNetFlow(_acceptedToken, address(this));
        // this is netFlow to Contract I think??? just divide it by amount of nft:s out there and it'll be alright?

        //(,int96 outFlowRate,,) = _cfa.getFlow(_acceptedToken, address(this), _receiver); // CHECK: unclear what happens if flow doesn't exist.
        //int96 inFlowRate = netFlowRate + outFlowRate;
    }

}
