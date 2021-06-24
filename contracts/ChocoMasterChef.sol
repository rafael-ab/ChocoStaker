// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {ChocoToken} from "./ChocoToken.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {SafeERC20} from "./libraries/SafeERC20.sol";
import {IUniswapV2Router} from "./interfaces/UniswapV2/IUniswapV2Router.sol";
import {IUniswapV2Factory} from "./interfaces/UniswapV2/IUniswapV2Factory.sol";

import "hardhat/console.sol";

contract ChocoMasterChef is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accChocoPerShare;
    }

    ChocoToken public choco;

    uint256 public constant BONUS_MULTIPLIER = 20;

    uint256 public chocoPerBlock;

    uint256 public poolInfoCount;
    mapping(uint256 => PoolInfo) public poolInfo;
    mapping(address => uint256) public poolInfoIndex;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public startBlock;

    uint256 public totalAllocPoint;

    IUniswapV2Router public router;

    event ChocoPotAdded(uint256 index, address token, uint256 allocationPoint);
    event IngredientsAdded(address user, uint256 amountETH, uint256 amountDAI);
    event ChocoPrepared(address user, address token, uint256 amount);
    event ChocoClaimed(address user, uint256 poolIndex, uint256 reward);

    function initialize(
        address _chocoToken,
        uint256 _chocoPerBlock,
        uint256 _startBlock
    ) external initializer {
        __Ownable_init();
        choco = ChocoToken(_chocoToken);
        chocoPerBlock = _chocoPerBlock;
        startBlock = _startBlock;
        totalAllocPoint = 0;
        poolInfoCount = 1;
        router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    }

    function addChocoPot(
        uint256 _allocPoint,
        address _token,
        address _lpToken
    ) external onlyOwner {
        require(
            poolInfoIndex[_token] == 0,
            "ChocoMasterChef: Oups! There's enough of this ingredient"
        );

        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfoIndex[_token] = poolInfoCount;
        poolInfo[poolInfoCount++] = PoolInfo({
            lpToken: IERC20(_lpToken),
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accChocoPerShare: 0
        });

        emit ChocoPotAdded(poolInfoCount - 1, _token, _allocPoint);
    }

    function addIngredients(
        address token,
        uint256 amount,
        uint256 preparationDeadline
    ) external payable {
        _addIngredients(token, amount, msg.sender, preparationDeadline);
    }

    // add liquidity
    function _addIngredients(
        address token,
        uint256 amount,
        address to,
        uint256 preparationDeadline
    ) internal returns (uint256) {
        require(token != address(0), "ChocoMasterChef: No ingredients");
        uint256 poolIndex = poolInfoIndex[token];
        require(
            poolIndex > 0,
            "ChocoMasterChef: Oups! Bad ingredient for Choco recipe"
        );
        require(
            amount > 0 && msg.value > 0,
            "ChocoMasterChef: No enough ingredients"
        );
        require(
            preparationDeadline > block.timestamp,
            "ChocoMasterChef: Sorry, the choco was already melted"
        );

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeApprove(address(router), amount);

        (, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{
            value: msg.value
        }(token, amount, 1, 1, to, preparationDeadline);

        // refunds leftover ETH to the sender
        msg.sender.transfer(msg.value - amountETH);

        emit IngredientsAdded(msg.sender, msg.value, amount);

        return liquidity;
    }

    function prepareChoco(address token, uint256 amount) external {
        _prepareChoco(token, amount, msg.sender);
    }

    // stake
    function _prepareChoco(
        address token,
        uint256 amount,
        address from
    ) internal {
        uint256 _pid = poolInfoIndex[token];
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (from != address(this)) {
            pool.lpToken.safeTransferFrom(msg.sender, address(this), amount);
        }
        user.amount = user.amount.add(amount);
        user.rewardDebt = user.amount.mul(pool.accChocoPerShare).div(1e12);
        emit ChocoPrepared(msg.sender, token, amount);
    }

    function prepareChocoWithPermit() external {}

    function addIngredientsAndPrepareChoco(
        address token,
        uint256 amount,
        uint256 preparationDeadline
    ) external payable {
        uint256 liquidity = _addIngredients(
            token,
            amount,
            address(this),
            preparationDeadline
        );
        _prepareChoco(token, liquidity, address(this));

        emit IngredientsAdded(msg.sender, msg.value, amount);
        emit ChocoPrepared(msg.sender, token, liquidity);
    }

    function claimChoco(address token) external {
        uint256 _pid = poolInfoIndex[token];
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 reward = user.amount.mul(pool.accChocoPerShare).div(1e12).sub(
            user.rewardDebt
        );
        safeChocoTransfer(msg.sender, reward);
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit ChocoClaimed(msg.sender, _pid, reward);
    }

    function getMultiplier(uint256 from, uint256 to)
        public
        pure
        returns (uint256)
    {
        return
            to > from
                ? to.sub(from).mul(BONUS_MULTIPLIER)
                : from.add(1).sub(to).mul(BONUS_MULTIPLIER);
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 chocoReward = multiplier
        .mul(chocoPerBlock)
        .mul(pool.allocPoint)
        .div(totalAllocPoint);
        choco.mint(address(this), chocoReward);
        pool.accChocoPerShare = pool.accChocoPerShare.add(
            chocoReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    function safeChocoTransfer(address _to, uint256 _amount) internal {
        uint256 chocoBal = choco.balanceOf(address(this));
        if (_amount > chocoBal) {
            choco.transfer(_to, chocoBal);
        } else {
            choco.transfer(_to, _amount);
        }
    }

    receive() external payable {}
}
