// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// https://etherscan.io/address/0x10189c3abd3a638102b149fd9ffc9b6c7fb42fc9

contract ETHERC20PaymentHistoryWithSignature is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public usdtToken; // ERC20 token address
    address public backendSigner; // Signer address
    uint8 public tokenDecimals; // Token decimals

    mapping(uint256 => uint256) public recordHistory;

    event BackendSignerUpdated(
        address indexed oldSigner,
        address indexed newSigner
    );

    event TokenDecimalsUpdated(uint8 oldDecimals, uint8 newDecimals);

    constructor(
        address _usdtTokenAddress,
        address _backendSigner,
        uint8 _decimals
    ) Ownable(msg.sender) {
        require(_usdtTokenAddress != address(0), "Invalid token address");
        require(_backendSigner != address(0), "Invalid signer address");

        usdtToken = IERC20(_usdtTokenAddress);
        backendSigner = _backendSigner;
        tokenDecimals = _decimals;
    }

    function transferUSDTWithRecord(
        bytes memory signedSig,
        bytes memory signedMsg
    ) public {
        // Decode signedSig
        (bytes32 r, bytes32 s, uint8 v) = abi.decode(
            signedSig,
            (bytes32, bytes32, uint8)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(signedMsg)
            )
        );

        address recoveredSigner = ecrecover(hash, v, r, s);

        // Verify signature
        require(recoveredSigner == backendSigner, "Invalid signature");

        // Decode signedMsg
        (
            address from,
            address to,
            uint256 recordId,
            uint256 amount,
            uint256 deadline
        ) = abi.decode(
                signedMsg,
                (address, address, uint256, uint256, uint256)
            );

        // Check if payment recordId is already used
        require(recordHistory[recordId] == 0, "Payment record already used");

        // Calculate adjusted amount
        uint256 adjustedAmount = amount * (10 ** uint256(tokenDecimals));

        // Balance check
        require(
            usdtToken.balanceOf(from) >= adjustedAmount,
            "Insufficient balance"
        );

        // Allowance check
        require(
            usdtToken.allowance(from, address(this)) >= adjustedAmount,
            "Not enough allowance"
        );

        // Timeout check
        require(block.timestamp <= deadline, "Transaction expired");

        // Safe transfer
        usdtToken.safeTransferFrom(from, to, adjustedAmount);

        // Mark as processed
        recordHistory[recordId] = block.number;
    }

    // Change signer address
    function updateBackendSigner(address _newBackendSigner) external onlyOwner {
        require(
            _newBackendSigner != address(0),
            "New signer cannot be the zero address"
        );
        require(
            _newBackendSigner != backendSigner,
            "New signer must be different from current signer"
        );

        emit BackendSignerUpdated(backendSigner, _newBackendSigner);
        backendSigner = _newBackendSigner;
    }

    // Update token decimals (only by contract owner)
    function updateTokenDecimals(uint8 _newDecimals) external onlyOwner {
        require(_newDecimals > 0, "Decimals must be greater than 0");

        emit TokenDecimalsUpdated(tokenDecimals, _newDecimals);
        tokenDecimals = _newDecimals;
    }
}
