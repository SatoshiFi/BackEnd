// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IBIP340Verifier.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BIP340Adapter is Ownable {
    IBIP340Verifier public verifier;

    // Конструктор, передающий initialOwner в Ownable и инициализирующий verifier
    constructor(address initialOwner, address _verifier) Ownable(initialOwner) {
        require(_verifier != address(0), "Invalid verifier address");
        verifier = IBIP340Verifier(_verifier);
    }

    function setVerifier(address _verifier) external onlyOwner {
        require(_verifier != address(0), "Invalid verifier address");
        verifier = IBIP340Verifier(_verifier);
    }

    function verify(
        uint256 pubX,
        uint256 pubY, // сохраняем сигнатуру для совместимости
        uint256 rx,
        uint256 ry,
        uint256 s,
        bytes32 msgHash
    ) external view returns (bool) {
        return verifier.verifySchnorr(pubX, pubY, rx, ry, s, msgHash);
    }
}