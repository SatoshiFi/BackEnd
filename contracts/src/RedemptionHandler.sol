// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IPoolMpToken.sol";
import "./interfaces/IFROSTCoordinator.sol";
import "./interfaces/IMiningPoolCore.sol";

contract RedemptionHandler {
    struct Redemption {
        address requester;
        uint64 amountSat;
        bytes btcScript;
        uint256 requestedAt;
        bool isConfirmed;
        uint256 frostSessionId;
    }

    mapping(address => mapping(uint256 => Redemption)) public poolRedemptions;
    mapping(address => uint256) public poolRedemptionCounter;

    event RedemptionRequested(address indexed pool, uint256 indexed id, address requester, uint64 amount);
    event RedemptionConfirmed(address indexed pool, uint256 indexed id, bool ok);

    function requestRedemption(
        address requester,
        uint64 amountSat,
        bytes calldata btcScript,
        address pool
    ) external returns (uint256) {
        require(amountSat > 0, "zero amount");
        require(btcScript.length > 0, "empty script");

        // Get MP token from pool
        address mpToken = getMpTokenForPool(pool);

        // Burn MP tokens from requester
        IPoolMpToken(mpToken).burn(requester, amountSat);

        uint256 redemptionId = poolRedemptionCounter[pool]++;

        poolRedemptions[pool][redemptionId] = Redemption({
            requester: requester,
            amountSat: amountSat,
            btcScript: btcScript,
            requestedAt: block.timestamp,
            isConfirmed: false,
            frostSessionId: 0
        });

        emit RedemptionRequested(pool, redemptionId, requester, amountSat);
        return redemptionId;
    }

    function confirmRedemption(
        uint256 redemptionId,
        bool ok,
        address pool
    ) external {
        Redemption storage r = poolRedemptions[pool][redemptionId];
        require(r.requester != address(0), "not found");
        require(!r.isConfirmed, "already confirmed");

        r.isConfirmed = true;

        if (!ok) {
            // Refund MP tokens
            address mpToken = getMpTokenForPool(pool);
            IPoolMpToken(mpToken).mint(r.requester, r.amountSat);
        }

        emit RedemptionConfirmed(pool, redemptionId, ok);
    }

    function getMpTokenForPool(address pool) internal view returns (address) {
        // Get MP token from the pool's storage
        // The pool should have poolToken set during creation
        try IMiningPoolCore(pool).poolToken() returns (address token) {
            return token;
        } catch {
            // Fallback - pool might not have the getter
            return address(0);
        }
    }
}