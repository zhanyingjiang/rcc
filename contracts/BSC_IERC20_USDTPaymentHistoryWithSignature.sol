// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// https://bscscan.com/address/0x5c514C5543Fd5C8456B99EFAECA3bC909F870470

contract BSCIERC20PaymentHistoryWithSignature is Ownable {
    IERC20 public usdtToken; // 代币地址
    address public backendSigner; // 签名地址
    uint8 public tokenDecimals; // 精度

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
        usdtToken = IERC20(_usdtTokenAddress);
        backendSigner = _backendSigner;
        tokenDecimals = _decimals;
    }

    function transferUSDTWithRecord(
        bytes memory signedSig,
        bytes memory signedMsg
    ) public {
        // 解析 signedSig
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

        // 签名检查
        require(recoveredSigner == backendSigner, "Invalid signature");

        // 解析 signedMsg
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

        // 检查 paymentRecordId 是否已经被使用
        require(recordHistory[recordId] == 0, "Payment record already used");

        // 计算调整后的金额
        uint256 adjustedAmount = amount * (10**uint256(tokenDecimals));

        // 余额检查
        require(
            usdtToken.balanceOf(from) >= adjustedAmount,
            "Insufficient balance"
        );

        // 动账检查
        require(
            usdtToken.allowance(from, address(this)) >= adjustedAmount,
            "Not enough allowance"
        );

        // 超时检查
        require(block.timestamp <= deadline, "Transaction expired");

        require(
            usdtToken.transferFrom(from, to, adjustedAmount),
            "Transfer failed"
        );

        // 标记已处理
        recordHistory[recordId] = block.number;
    }

    // 变更签名用户
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

    // 更新代币精度（只能由合约所有者调用）
    function updateTokenDecimals(uint8 _newDecimals) external onlyOwner {
        require(_newDecimals > 0, "Decimals must be greater than 0");

        emit TokenDecimalsUpdated(tokenDecimals, _newDecimals); // 触发事件
        tokenDecimals = _newDecimals;
    }
}
