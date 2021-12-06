pragma solidity ^0.8.0;

import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

interface ILongTermPeople is IERC721 {
    // add events m8
    function mint() external returns (uint256);

    function issueNft(address to, uint256 tokenId, uint256 amount, string memory tokenURI) external payable;

    function getNextId() external view returns (uint256);

    function burnNft() external;

    function withdrawEth() external payable;

    function createAuction() external;
}