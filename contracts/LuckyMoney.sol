// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./lib/ERC20/IERC20.sol";
import "./lib/ERC20/SafeERC20.sol";

import "./lib/Context.sol";
import "./lib/ReentrancyGuard.sol";
import "./proxy/Initializable.sol";

// Airdrop as LuckyMoney
contract LuckyMoney is Context, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Record {
        address collector;
        bytes32 seed;
    }

    struct LuckyMoneyData {
        address creator;
        uint256 expireTime;
        // 0 for random, 1 for fixed
        uint8 mode;
        address tokenAddr;
        uint256 tokenAmount;
        uint256 collectorCount;
        uint256 nonce;
        uint256 refundAmount;
        mapping (address => bool) collectStatus;
        mapping (uint256 => Record) records;
    }

    mapping (bytes32 => LuckyMoneyData) public luckyMoneys;

    struct RewardConfig {
        uint256 forSender;
        uint256 forReceiver;
    }

    address[] public rewards;
    mapping (address => RewardConfig) public rewardConfigs;
    mapping (address => uint256) public rewardBalances;

    event Disperse(
        address indexed _sender,
        address _tokenAddr,
        uint256 _tokenAmount,
        uint256 _fee
    );
    event Create(
        bytes32 indexed _id,
        address _tokenAddr,
        uint256 _tokenAmount,
        uint256 _expireTime,
        uint256 _collectorCount,
        uint256 _fee,
        uint256 _gasRefund
    );
    event Collect(
        address indexed _collector,
        address indexed _tokenAddress,
        // 0 for disperse, 1 for luckyMoney
        uint8 _mode,
        uint256 _tokenAmount,
        bytes32 _id
    );
    event Distribute(
        bytes32 indexed _id,
        address indexed _caller,
        uint256 _remainCollector,
        uint256 _remainTokenAmount
    );
    event RewardCollect(
        address indexed _collector,
        address indexed _tokenAddr,
        // 0 for send, 1 for receive
        uint8 _mode,
        uint256 amount);
    event FeeRateUpdate(uint16 feeRate);
    event FeeReceiverUpdate(address receiver);
    event OwnershipUpdate(address oldOwner, address newOwner);

    address public owner;
    uint256 public refundAmount = 1e15; // 0.001

    // Fee = total * feeRate / feeBase
    // For example, feeRate as 100 means 1% fee.
    uint16 public feeRate = 10;
    uint16 public feeBase = 10000;
    address public feeReceiver;

    constructor() public {}

    function initialize(address _owner, address _feeReceiver) external initializer {
        owner = _owner;
        feeReceiver = _feeReceiver;

        feeRate = 10;
        feeBase = 10000;
        refundAmount = 1e15;

    }

    // ========= Normal disperse =========

    function disperseEther(address payable[] memory recipients, uint256[] memory values) external payable {
        address sender = msg.sender;
        uint256 total = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            total += values[i];
        }
        uint256 fee = takeFeeAndValidate(sender, msg.value, address(0), total);
        giveReward(sender, 0);
        emit Disperse(sender, address(0), total, fee);

        for (uint256 i = 0; i < recipients.length; i++) {
            recipients[i].transfer(values[i]);
            emit Collect(recipients[i], address(0), 1, values[i], 0);
            giveReward(recipients[i], 1);
        }
    }

    function disperseToken(IERC20 token, address[] memory recipients, uint256[] memory values) external {
        address sender = msg.sender;
        uint256 total = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            total += values[i];
        }
        uint256 fee = takeFeeAndValidate(sender, 0, address(token), total);
        giveReward(sender, 0);
        emit Disperse(sender, address(token), total, fee);

        for (uint256 i = 0; i < recipients.length; i++) {
            token.safeTransfer(recipients[i], values[i]);
            emit Collect(recipients[i], address(token), 1, values[i], 0);
            giveReward(recipients[i], 1);
        }
    }

    // ========= LuckyMoney which need signature to collect =========
    function create(
        uint256 expireTime, 
        uint8 mode, 
        address tokenAddr, 
        uint256 tokenAmount, 
        uint256 collectorCount) 
        external payable returns (bytes32) {

        address sender = msg.sender;
        uint256 value = msg.value;

        require(value >= refundAmount, "not enough to refund later");
        uint256 fee = takeFeeAndValidate(sender, msg.value - refundAmount, tokenAddr, tokenAmount);

        bytes32 luckyMoneyId = getLuckyMoneyId(sender, block.timestamp, tokenAddr, tokenAmount, collectorCount);
        LuckyMoneyData storage l = luckyMoneys[luckyMoneyId];
        l.creator = sender;
        l.expireTime = expireTime;
        l.mode = mode;
        l.tokenAddr = tokenAddr;
        l.tokenAmount = tokenAmount;
        l.collectorCount = collectorCount;
        l.refundAmount = refundAmount;
        emit Create(luckyMoneyId, tokenAddr, tokenAmount, expireTime, collectorCount, fee, refundAmount);
        giveReward(sender, 0);

        return luckyMoneyId;
    }

    function submit(bytes32 luckyMoneyId, bytes memory signature) external {
        address sender = msg.sender;
        LuckyMoneyData storage l = luckyMoneys[luckyMoneyId];
        require(!hasCollected(luckyMoneyId, sender), "collected before");
        require(l.nonce < l.collectorCount, "collector count exceed");

        // Verify signature
        bytes32 hash = getEthSignedMessageHash(luckyMoneyId, sender);
        require(recoverSigner(hash, signature) == l.creator, "signature not signed by creator");
        l.records[l.nonce] = Record(sender, getBlockAsSeed(sender));
        l.nonce += 1;
        l.collectStatus[sender] = true;
    }

    function distribute(bytes32 luckyMoneyId) external {
        LuckyMoneyData storage l = luckyMoneys[luckyMoneyId];
        require(l.nonce == l.collectorCount || block.timestamp > l.expireTime, "luckyMoney not fully collected or expired");
        // generate amounts
        address payable[] memory recipients = new address payable[](l.nonce);
        uint256[] memory values = new uint256[](l.nonce);
        uint256 remainCollectorCount = l.collectorCount;
        uint256 remainTokenAmount = l.tokenAmount;

        if (l.mode == 1) {
            // - Fix mode
            uint256 avgAmount = l.tokenAmount / l.collectorCount;
            remainCollectorCount = l.collectorCount - l.nonce;
            remainTokenAmount = l.tokenAmount - avgAmount * l.nonce;
            for (uint256 i = 0; i < l.nonce; i++) {
                recipients[i] = payable(l.records[i].collector);
                values[i] = avgAmount;
            }
        } else if (l.mode == 0) {

            // - Random mode
            bytes32 seed;
            for (uint256 i = 0; i < l.nonce; i++) {
                seed = seed ^ l.records[i].seed;
            }

            for (uint256 i = 0; i < l.nonce; i++) {
                recipients[i] = payable(l.records[i].collector);
                values[i] = calculateRandomAmount(seed, l.records[i].seed, remainTokenAmount, remainCollectorCount);
                remainCollectorCount -= 1;
                remainTokenAmount -= values[i];
            }
        }

        address tokenAddr = l.tokenAddr;
        address creator = l.creator;
        uint256 _refundAmount = l.refundAmount;
        // prevent reentrency attack, delete state before calling external transfer
        delete luckyMoneys[luckyMoneyId];

        // distribute
        if (tokenAddr == address(0)) {
            // - ETH
            for (uint256 i = 0; i < recipients.length; i++) {
                recipients[i].transfer(values[i]);
                emit Collect(recipients[i], tokenAddr, 2, values[i], luckyMoneyId);
                giveReward(recipients[i], 1);
            }
            // return exceed ethers to creator
            payable(creator).transfer(remainTokenAmount);
        } else {

            // - Token
            IERC20 token = IERC20(tokenAddr);
            for (uint256 i = 0; i < recipients.length; i++) {
                token.safeTransfer(recipients[i], values[i]);
                emit Collect(recipients[i], tokenAddr, 2, values[i], luckyMoneyId);
                giveReward(recipients[i], 1);
            }
            // return exceed tokens to creator
            token.transfer(creator, remainTokenAmount);
        }
        
        address sender = msg.sender;
        // refund caller
        payable(sender).transfer(_refundAmount);
        emit Distribute(luckyMoneyId, sender, remainCollectorCount, remainTokenAmount);
    }

    // ========= Admin functions =========

    function setOwner(address _owner) external {
        require(msg.sender == owner, "priviledged action");

        emit OwnershipUpdate(owner, _owner);
        owner = _owner;
    }

    function setRefundAmount(uint256 _amount) external {
        require(msg.sender == owner, "priviledged action");

        refundAmount = _amount;
    }

    function setFeeRate(uint16 _feeRate) external {
        require(msg.sender == owner, "priviledged action");
        require(_feeRate <= 10000, "fee rate greater than 100%");

        feeRate = _feeRate;
        emit FeeRateUpdate(_feeRate);
    }

    function setFeeReceiver(address _receiver) external {
        require(msg.sender == owner, "priviledged action");
        require(_receiver != address(0), "fee receiver can't be zero address");

        feeReceiver = _receiver;
        emit FeeReceiverUpdate(_receiver);
    }

    function setRewardTokens(address[] calldata rewardTokens) external {
        require(msg.sender == owner, "priviledged action");

        rewards = rewardTokens;
    }

    function configRewardRate(address rewardToken, uint256 forSender, uint256 forReceiver) external {
        require(msg.sender == owner, "priviledged action");

        rewardConfigs[rewardToken] = RewardConfig(forSender, forReceiver);
    }

    function addReward(address tokenAddr, uint256 amount) external {
        IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), amount);
        rewardBalances[tokenAddr] += amount;
    }

    function withdrawReward(address tokenAddr, uint256 amount) external {
        require(msg.sender == owner, "priviledged action");
        require(rewardBalances[tokenAddr] >= amount, "remain reward not enough to withdraw");

        IERC20(tokenAddr).safeTransfer(owner, amount);
        rewardBalances[tokenAddr] -= amount;
    }

    // ========= View functions =========

    function hasCollected(bytes32 luckyMoneyId, address collector) public view returns (bool) {
        return luckyMoneys[luckyMoneyId].collectStatus[collector];
    }

    function expireTime(bytes32 luckyMoneyId) public view returns (uint256) {
        return luckyMoneys[luckyMoneyId].expireTime;
    }

    function feeOf(uint256 amount) public view returns (uint256) {
        return amount * feeRate / feeBase;
    }

    // ========= Util functions =========

    function takeFeeAndValidate(address sender, uint256 value, address tokenAddr, uint256 tokenAmount) internal returns (uint256 fee) {
        fee = feeOf(tokenAmount);
        if (tokenAddr == address(0)) {
            require(value == tokenAmount + fee, "incorrect amount of eth transferred");
            payable(feeReceiver).transfer(fee);
        } else {
            require(IERC20(tokenAddr).balanceOf(msg.sender) >= tokenAmount + fee, "incorrect amount of token transferred");
            IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), tokenAmount);
            IERC20(tokenAddr).safeTransferFrom(msg.sender, address(feeReceiver), fee);
        }
    }

    function giveReward(address target, uint8 mode) internal {
        for (uint256 i = 0; i < rewards.length; i++) {
            address token = rewards[i];
            RewardConfig storage config = rewardConfigs[token];
            uint256 amount = mode == 0 ? config.forSender : config.forReceiver;
            if (amount > 0 && rewardBalances[token] > amount) {
                rewardBalances[token] -= amount;
                IERC20(token).safeTransfer(target, amount);
                emit RewardCollect(target, token, mode, amount);
            }
        }
    }

    // TODO will chainId matters? for security?
    function getLuckyMoneyId(
        address _creator,
        uint256 _startTime,
        address _tokenAddr,
        uint256 _tokenAmount,
        uint256 _collectorCount
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_creator, _startTime, _tokenAddr, _tokenAmount, _collectorCount));
    }

    function getBlockAsSeed(address addr) public view returns (bytes32) {
        return keccak256(abi.encode(addr, block.timestamp, block.difficulty, block.number));
    }

    function calculateRandomAmount(bytes32 rootSeed, bytes32 seed, uint256 remainAmount, uint remainCount) public pure returns (uint256) {
        uint256 amount = 0;
        if (remainCount == 1) {
            amount = remainAmount;
        } else if (remainCount == remainAmount) {
            amount = 1;
        } else if (remainCount < remainAmount) {
            amount = uint256(keccak256(abi.encode(rootSeed, seed))) % (remainAmount / remainCount * 2) + 1;
        }
        return amount;
    }

    function getMessageHash(
        bytes32 _luckyMoneyId,
        address _collector
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_luckyMoneyId, _collector));
    }

  function getEthSignedMessageHash(
        bytes32 _luckyMoneyId,
        address _collector
  )
        public
        pure
        returns (bytes32)
    {
        bytes32 _messageHash = getMessageHash(_luckyMoneyId, _collector);
        /*
        Signature is produced by signing a keccak256 hash with the following format:
        "\x19Ethereum Signed Message\n" + len(msg) + msg
        */
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
            );
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature)
        public
        pure
        returns (address)
    {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig)
        public
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }
        // implicitly return (r, s, v)
    }

    function GetInitializeData(address _owner, address _feeReceiver) public pure returns(bytes memory){
        return abi.encodeWithSignature("initialize(address,address)", _owner,_feeReceiver);
    }

    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
