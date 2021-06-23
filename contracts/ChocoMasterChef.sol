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

    event IngredientsAdded(address user, uint256 amountETH, uint256 amountDAI);
    event ChocoPrepared(address user, address lpToken, uint256 amount);

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

    function add(
        uint256 _allocPoint,
        address _token,
        address _lpToken
    ) public onlyOwner {
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
    }

    // add liquidity
    function addIngredients(
        address token,
        uint256 amount,
        uint256 preparationDeadline
    ) external payable {
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

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router
        .addLiquidityETH{value: msg.value}(
            token,
            amount,
            1,
            1,
            msg.sender,
            preparationDeadline
        );

        // refunds leftover ETH to the sender
        msg.sender.transfer(msg.value - amountETH);

        emit IngredientsAdded(msg.sender, msg.value, amount);
    }

    // stake
    function prepareChoco(address _token, uint256 _amount) external {
        uint256 _pid = poolInfoIndex[_token];
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accChocoPerShare).div(1e12);
        emit ChocoPrepared(msg.sender, address(pool.lpToken), _amount);
    }

    function prepareChocoWithPermit() external {}

    function addIngredientsAndPrepareChoco() external {}

    function claimChoco(address _token) external {
        uint256 _pid = poolInfoIndex[_token];
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
        // emit ChocoClaimed(msg.sender, _pid, reward);
    }

    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return
            _to > _from
                ? _to.sub(_from).mul(BONUS_MULTIPLIER)
                : _from.add(1).sub(_to).mul(BONUS_MULTIPLIER);
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
