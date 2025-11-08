// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.20;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC5192 } from "../interfaces/IERC5192.sol";

/**
 * @title Ecosystem Lead NFT
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Soulbound NFT representing DAO council membership
 * @dev Implements ERC-5192 for non-transferable tokens
 *
 *      SOULBOUND MECHANICS:
 *      ═══════════════════════════════════
 *      - NFTs are non-transferable (except burn)
 *      - Prevents vote selling/delegation attacks
 *      - Can be revoked by governance
 *      - Each address can hold max 1 NFT
 *
 *      MINTING MECHANISMS:
 *      ═══════════════════════════════════
 *      1. Owner Mint: Governance can directly mint
 *      2. Application + Vote: Community proposes, council votes
 *      3. Automatic: Based on contribution milestones
 *
 *      GOVERNANCE STRUCTURE:
 *      ═══════════════════════════════════
 *      - Owner can mint/revoke NFTs
 *      - Owner should be governance contract
 *      - Council members participate in ecosystem decisions
 *
 * @custom:security Soulbound prevents vote market
 * @custom:security One NFT per address prevents concentration
 */
contract EcosystemLeadNFT is ERC721, Ownable, IERC5192 {
    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Counter for token IDs
    uint256 private _nextTokenId;

    /// @notice Tracks which addresses hold NFTs (for O(1) lookup)
    mapping(address => bool) public isEcosystemLead;

    /// @notice Mapping from address to token ID
    mapping(address => uint256) public addressToTokenId;

    /// @notice Metadata URI base
    string private _baseTokenURI;

    /// @notice Total number of active council members
    uint256 public totalMembers;

    // ============================================
    // EVENTS
    // ============================================

    event LeadMinted(address indexed to, uint256 indexed tokenId);
    event LeadRevoked(address indexed from, uint256 indexed tokenId);
    event BaseURIUpdated(string newBaseURI);

    // ============================================
    // ERRORS
    // ============================================

    error AlreadyHasNFT(address holder);
    error NotALead(address addr);
    error TransferNotAllowed();
    error CannotTransferSoulbound();

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize EcosystemLeadNFT
     * @param _owner Governance contract address (can mint/revoke)
     * @param baseURI_ Base URI for token metadata
     */
    constructor(address _owner, string memory baseURI_) ERC721("Ecosystem Lead", "LEAD") Ownable(_owner) {
        _baseTokenURI = baseURI_;
        _nextTokenId = 1; // Start from token ID 1
    }

    // ============================================
    // MINTING FUNCTIONS
    // ============================================

    /**
     * @notice Mint ecosystem lead NFT to address
     * @dev Only owner (governance) can mint
     * @param to Address to receive NFT
     * @return tokenId Minted token ID
     */
    function mint(address to) external onlyOwner returns (uint256) {
        if (to == address(0)) revert ERC721InvalidReceiver(address(0));
        if (isEcosystemLead[to]) revert AlreadyHasNFT(to);

        uint256 tokenId = _nextTokenId++;

        _safeMint(to, tokenId);

        isEcosystemLead[to] = true;
        addressToTokenId[to] = tokenId;
        totalMembers++;

        emit LeadMinted(to, tokenId);
        emit Locked(tokenId); // ERC-5192 event

        return tokenId;
    }

    /**
     * @notice Batch mint NFTs to multiple addresses
     * @dev Only owner (governance) can mint
     * @param recipients Array of addresses to receive NFTs
     * @return tokenIds Array of minted token IDs
     */
    function batchMint(address[] calldata recipients) external onlyOwner returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](recipients.length);

        for (uint256 i = 0; i < recipients.length; i++) {
            address to = recipients[i];

            if (to == address(0)) revert ERC721InvalidReceiver(address(0));
            if (isEcosystemLead[to]) continue; // Skip if already has NFT

            uint256 tokenId = _nextTokenId++;

            _safeMint(to, tokenId);

            isEcosystemLead[to] = true;
            addressToTokenId[to] = tokenId;
            totalMembers++;

            tokenIds[i] = tokenId;

            emit LeadMinted(to, tokenId);
            emit Locked(tokenId);
        }

        return tokenIds;
    }

    // ============================================
    // REVOCATION FUNCTIONS
    // ============================================

    /**
     * @notice Revoke ecosystem lead NFT from address
     * @dev Only owner (governance) can revoke
     * @param from Address to revoke NFT from
     */
    function revoke(address from) external onlyOwner {
        if (!isEcosystemLead[from]) revert NotALead(from);

        uint256 tokenId = addressToTokenId[from];

        _burn(tokenId);

        isEcosystemLead[from] = false;
        delete addressToTokenId[from];
        totalMembers--;

        emit LeadRevoked(from, tokenId);
        emit Unlocked(tokenId); // ERC-5192 event
    }

    /**
     * @notice Batch revoke NFTs from multiple addresses
     * @dev Only owner (governance) can revoke
     * @param addresses Array of addresses to revoke from
     */
    function batchRevoke(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            address from = addresses[i];

            if (!isEcosystemLead[from]) continue; // Skip if not a lead

            uint256 tokenId = addressToTokenId[from];

            _burn(tokenId);

            isEcosystemLead[from] = false;
            delete addressToTokenId[from];
            totalMembers--;

            emit LeadRevoked(from, tokenId);
            emit Unlocked(tokenId);
        }
    }

    // ============================================
    // SOULBOUND OVERRIDES
    // ============================================

    /**
     * @notice Check if token is locked (soulbound)
     * @dev All tokens are permanently locked
     * @return True (all tokens are soulbound)
     */
    function locked(uint256) external pure override returns (bool) {
        return true;
    }

    /**
     * @notice Override transfer to prevent transfers
     * @dev Soulbound tokens cannot be transferred
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting (from == address(0)) and burning (to == address(0))
        // Prevent all other transfers
        if (from != address(0) && to != address(0)) {
            revert CannotTransferSoulbound();
        }

        return super._update(to, tokenId, auth);
    }

    // ============================================
    // METADATA FUNCTIONS
    // ============================================

    /**
     * @notice Get base URI for token metadata
     * @return Base URI string
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice Update base URI (governance only)
     * @param newBaseURI New base URI
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Check if address is an ecosystem lead
     * @param addr Address to check
     * @return bool True if address holds NFT
     */
    function isLead(address addr) external view returns (bool) {
        return isEcosystemLead[addr];
    }

    /**
     * @notice Get token ID for address
     * @param addr Address to query
     * @return tokenId Token ID (0 if none)
     */
    function tokenIdOf(address addr) external view returns (uint256) {
        return addressToTokenId[addr];
    }

    /**
     * @notice Get all current ecosystem leads
     * @dev Expensive operation, use off-chain for large sets
     * @return leads Array of lead addresses
     */
    function getAllLeads() external view returns (address[] memory leads) {
        uint256 total = totalMembers;
        leads = new address[](total);
        uint256 count = 0;

        // Iterate through all minted token IDs
        for (uint256 i = 1; i < _nextTokenId && count < total; i++) {
            address owner = _ownerOf(i);
            if (owner != address(0)) {
                leads[count++] = owner;
            }
        }

        return leads;
    }

    // ============================================
    // INTERFACE SUPPORT
    // ============================================

    /**
     * @notice Check interface support
     * @param interfaceId Interface ID to check
     * @return bool True if supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }
}