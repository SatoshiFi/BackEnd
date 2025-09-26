// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract PoolMembershipNFT is ERC721, ERC721URIStorage, AccessControl {
    using Strings for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    struct Membership {
        bytes32 poolId;
        bytes32 role;
        uint64  joinTimestamp;
        bool    active;
    }

    struct PayoutInfo {
        address evmPayout;     // куда зачислять mpToken/sToken
        string  btcAddress;    // человеко-читаемый BTC-адрес (для UI)
        bytes32 btcXOnlyPub;   // Taproot (32 байта) если есть
        bytes20 btcPubKeyHash; // P2WPKH (20 байт) если есть
    }

    // tokenId => membership data
    mapping(uint256 => Membership) public membershipOf;
    // tokenId => payout info
    mapping(uint256 => PayoutInfo) public payoutOf;
    // address => tokenId
    mapping(address => uint256) public tokenOf;

    uint256 public totalMinted;

    event MembershipMinted(address indexed to, uint256 indexed tokenId, bytes32 poolId, bytes32 role);
    event MembershipBurned(uint256 indexed tokenId);
    event PayoutUpdated(uint256 indexed tokenId, address evmPayout, string btcAddress);

    constructor(address admin) ERC721("Pool Membership (SBT)", "POOL-SBT") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    // ---------------- Core (SBT) ----------------

    function mint(
        address to,
        bytes32 poolId,
        bytes32 role,
        string calldata tokenURI_
    ) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        require(to != address(0), "zero addr");
        require(tokenOf[to] == 0, "already has membership");

        tokenId = ++totalMinted;
        _safeMint(to, tokenId);

        membershipOf[tokenId] = Membership({
            poolId: poolId,
            role: role,
            joinTimestamp: uint64(block.timestamp),
            active: true
        });

        tokenOf[to] = tokenId;

        if (bytes(tokenURI_).length != 0) {
            _setTokenURI(tokenId, tokenURI_);
        }

        emit MembershipMinted(to, tokenId, poolId, role);
    }

    function burn(uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(
            _msgSender() == owner || hasRole(ADMIN_ROLE, _msgSender()),
            "not owner/admin"
        );
        _burn(tokenId);
        membershipOf[tokenId].active = false;
        if (tokenOf[owner] == tokenId) tokenOf[owner] = 0;
        emit MembershipBurned(tokenId);
    }

    // ---------------- Soulbound ----------------

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721)
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert("SBT: non-transferable");
        }
        return super._update(to, tokenId, auth);
    }

    // ---------------- Payout ----------------

    function setPayoutInfoWithAddress(
        uint256 tokenId,
        address evmPayout,
        string calldata btcAddress,
        bytes32 btcXOnlyPub,
        bytes20 btcPubKeyHash
    ) external {
        require(_ownerOf(tokenId) == _msgSender(), "not nft owner");
        require(membershipOf[tokenId].active, "membership inactive");

        payoutOf[tokenId] = PayoutInfo({
            evmPayout: evmPayout,
            btcAddress: btcAddress,
            btcXOnlyPub: btcXOnlyPub,
            btcPubKeyHash: btcPubKeyHash
        });

        emit PayoutUpdated(tokenId, evmPayout, btcAddress);
    }

    function buildP2WPKH(bytes20 pubKeyHash) public pure returns (bytes memory) {
        return abi.encodePacked(hex"0014", pubKeyHash);
    }

    function buildP2TR(bytes32 xOnlyPub) public pure returns (bytes memory) {
        return abi.encodePacked(hex"5120", xOnlyPub);
    }

    function btcScriptOf(uint256 tokenId) public view returns (bytes memory) {
        PayoutInfo memory p = payoutOf[tokenId];
        if (p.btcXOnlyPub != bytes32(0)) {
            return buildP2TR(p.btcXOnlyPub);
        }
        if (p.btcPubKeyHash != bytes20(0)) {
            return buildP2WPKH(p.btcPubKeyHash);
        }
        return bytes("");
    }

    // ---------------- Views/Utils ----------------

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return ERC721URIStorage.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
