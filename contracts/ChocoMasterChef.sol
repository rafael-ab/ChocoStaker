// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {ChocoToken} from "./ChocoToken.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {SafeERC20} from "./libraries/SafeERC20.sol";
import {IUniswapV2Router} from "./interfaces/UniswapV2/IUniswapV2Router.sol";
import {IUniswapV2Pair} from "./interfaces/UniswapV2/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "./interfaces/UniswapV2/IUniswapV2Factory.sol";

import "hardhat/console.sol";

/**
 * @title ChocoMasterChef Contract
 * @author Rafael Romero (@rafius97)
 * @notice ChocoMasterChef is the Choco maker, if you want choco,
 * you should interact with this guy...
 * @dev You can add liquidity with UniswapV2, stake UNI LP Tokens
 * and claim Choco Token rewards .
 */
contract ChocoMasterChef is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    struct UserInfo {
        // amount of LP tokens
        uint256 amount;
        // amount of reward in Choco Tokens
        uint256 rewardDebt;
    }

    struct PoolInfo {
        // ERC20 UniswapV2 Liquidity Pool Tokens
        IERC20 lpToken;
        // amount of allocations point of the pool
        uint256 allocPoint;
        // last block number rewarded
        uint256 lastRewardBlock;
        // accumulated Choco Token, updated every time a user stake its LP tokens
        uint256 accChocoPerShare;
    }

    /**
     * @notice ERC20 representation of the Choco Token
     * @return Address of the Choco Token
     */
    ChocoToken public choco;

    /**
     * @notice Bonus multiplier of reward
     */
    uint256 public constant BONUS_MULTIPLIER = 20;

    /**
     * @notice Amount of Choco Token created per block
     */
    uint256 public chocoPerBlock;

    /**
     * @notice Index of the UniswapV2 LP
     */
    uint256 public poolInfoCount;

    /**
     * @notice Mapping of PoolInfo
     */
    mapping(uint256 => PoolInfo) public poolInfo;

    /**
     * @notice Mapping from a LP address to its index
     */
    mapping(address => uint256) public poolInfoIndex;

    /**
     * @notice Mapping of UserInfo giver a UniswapV2 LP
     */
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /**
     * @notice Block number when Choco Token starts "mining"
     */
    uint256 public startBlock;

    /**
     * @notice Total amount of allocations points of the UniswapV2 LP
     */
    uint256 public totalAllocPoint;

    /**
     * @notice Representation of the UniswapV2 Router
     * @return The address of the UniswapV2 Router
     */
    IUniswapV2Router public router;

    event ChocoPotAdded(
        uint256 index,
        address lpToken,
        uint256 allocationPoint
    );
    event IngredientsAdded(
        address user,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    );
    event ChocoPrepared(address user, address lpToken, uint256 amount);
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

    /**
     * @notice Adds a new Choco Pot to fill with choco
     * @dev Adds a new UniswapV2 Liquidity Pool to the contract
     * @param _allocPoint Amount of allocation point to be assign to this pool
     * @param _lpToken The address of the UniswapV2 Liquidity Pool
     *
     * Emits a {ChocoPotAdded} event.
     */
    function addChocoPot(uint256 _allocPoint, address _lpToken)
        external
        onlyOwner
    {
        require(
            poolInfoIndex[_lpToken] == 0,
            "ChocoMasterChef: Oups! There's enough of this ingredient"
        );

        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;

        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo[++poolInfoCount] = PoolInfo({
            lpToken: IERC20(_lpToken),
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accChocoPerShare: 0
        });
        poolInfoIndex[_lpToken] = poolInfoCount;

        emit ChocoPotAdded(poolInfoCount, _lpToken, _allocPoint);
    }

    /**
     * @dev Swaps `_amount` of `_token0` to `_token1` from `_pool` using UniswapV2
     * @param _pool The address of the UniswapV2 Liquidity Pool
     * @param _token0 Address of the token to be swapped
     * @param _token1 Address of the token after to swap
     * @param _amount Amount of the `_token0` to be swapped
     */
    function _swap(
        address _pool,
        address _token0,
        address _token1,
        uint256 _amount
    ) internal returns (uint256) {
        require(_pool != address(0), "ChocoMasterChef: No ChocoPot to mix");
        require(
            _token0 != _token1,
            "ChocoMasterChef: You need more ingredients to mix, no just one"
        );
        require(_amount > 0, "ChocoMasterChef: No enough ingredients to mix");

        IWETH weth = IWETH(router.WETH());

        if (_token0 == address(weth)) {
            weth.deposit{value: _amount}();
        } else {
            if (IERC20(_token0).allowance(msg.sender, address(this)) > 0) {
                IERC20(_token0).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _amount
                );
            }
        }

        IUniswapV2Pair pair = IUniswapV2Pair(_pool);
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        IERC20 token0 = address(weth) == _token0
            ? IERC20(address(weth))
            : IERC20(_token0);

        uint256 amountOutWithSlippage;
        if (_token0 == pair.token0()) {
            token0.safeTransfer(address(pair), _amount);
            uint256 amountOut = _amount.mul(reserve1) / reserve0;
            amountOutWithSlippage = amountOut.mul(996).div(1000);
            pair.swap(0, amountOutWithSlippage, address(this), "");
        } else {
            token0.safeTransfer(address(pair), _amount);
            uint256 amountOut = _amount.mul(reserve0) / reserve1;
            amountOutWithSlippage = amountOut.mul(996).div(1000);
            pair.swap(amountOutWithSlippage, 0, address(this), "");
        }

        /* if (_token1 == address(weth)) {
            weth.withdraw(weth.balanceOf(address(this)));
        } */

        return amountOutWithSlippage;
    }

    /**
     * @notice Add ingredients to a Choco Pot
     * @dev See {_addIngredients}
     * @param lpToken The address of the Choco Pot
     * @param tokenA Address of the tokenA ingredient to be added to the Choco Pot
     * @param tokenB Address of the tokenB ingredient to be added to the Choco Pot
     * @param amountA Amount of the `tokenA` ingredient to be added
     * @param amountB Amount of the `tokenB` ingredient to be added
     * @param preparationDeadline Maximum amount of time to add the ingredients
     *
     * Emits a {IngredientsAdded} event.
     */
    function addIngredients(
        address lpToken,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 preparationDeadline
    ) external payable {
        _addIngredients(
            lpToken,
            tokenA,
            tokenB,
            amountA,
            amountB,
            msg.sender,
            preparationDeadline
        );
    }

    function mixingAndAddIngredientsAndPrepareChoco(
        address tokenA,
        address tokenB,
        address tokenPayment,
        uint256 amountPayment,
        uint256 preparationDeadline
    ) external payable {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        ) = _mixingAndAddIngredients(
            factory,
            tokenA,
            tokenB,
            tokenPayment,
            amountPayment,
            preparationDeadline
        );

        address lpToken = IUniswapV2Factory(router.factory()).getPair(
            tokenA,
            tokenB
        );

        _prepareChoco(lpToken, liquidity, address(this));

        emit IngredientsAdded(msg.sender, tokenA, tokenB, amountA, amountB);
        emit ChocoPrepared(msg.sender, lpToken, liquidity);
    }

    /**
     * @notice Mix and add ingredients to a Choco Pot
     * @dev See {_mixingAndAddIngredients}
     * @param tokenA Address of the tokenA ingredient to be added to the Choco Pot
     * @param tokenB Address of the tokenB ingredient to be added to the Choco Pot
     * @param tokenPayment Address of the tokenPayment ingredient to mix tokenA and Tokenb
     * @param amountPayment Amount of tokenPayment to be mixed
     * @param preparationDeadline Maximum amount of time to mix and to add the ingredients
     *
     * Emits a {IngredientsAdded} event.
     */
    function mixingAndAddIngredients(
        address tokenA,
        address tokenB,
        address tokenPayment,
        uint256 amountPayment,
        uint256 preparationDeadline
    ) external payable {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        _mixingAndAddIngredients(
            factory,
            tokenA,
            tokenB,
            tokenPayment,
            amountPayment,
            preparationDeadline
        );
    }

    /**
     * @dev First, swaps the ´tokenPayment´ to TokenA, then swaps
     * @dev the half of the TokenA to TokenB to get some proportionals amount
     * @param tokenA Address of the tokenA ingredient to be added to the Choco Pot
     * @param tokenB Address of the tokenB ingredient to be added to the Choco Pot
     * @param tokenPayment Address of the tokenPayment ingredient to mix tokenA and Tokenb
     * @param amountPayment Amount of tokenPayment to be mixed
     * @param preparationDeadline Maximum amount of time to mix and to add the ingredients
     * @return Amount of UniswapV2 LP Tokens
     *
     * Emits a {IngredientsAdded} event.
     */
    function _mixingAndAddIngredients(
        IUniswapV2Factory factory,
        address tokenA,
        address tokenB,
        address tokenPayment,
        uint256 amountPayment,
        uint256 preparationDeadline
    )
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(
            tokenPayment != address(0) ||
                tokenA != address(0) ||
                tokenB != address(0)
        );
        require(tokenPayment != tokenA && tokenPayment != tokenB);
        if (tokenPayment == router.WETH()) {
            require(msg.value > 0 && amountPayment == msg.value);
        } else {
            require(amountPayment > 0);
        }

        uint256 amountAOut = _swap(
            factory.getPair(tokenPayment, tokenA),
            tokenPayment,
            tokenA,
            amountPayment
        );

        address lpToken = factory.getPair(tokenA, tokenB);

        uint256 amountBOut = _swap(lpToken, tokenA, tokenB, amountAOut / 2);

        IERC20 _tokenA = IERC20(tokenA);
        IERC20 _tokenB = IERC20(tokenB);

        _tokenA.safeApprove(address(router), amountAOut / 2);
        _tokenB.safeApprove(address(router), amountBOut);

        (uint256 addedAmountA, uint256 addedAmountB, uint256 liquidity) = router
        .addLiquidity(
            address(_tokenA),
            address(_tokenB),
            amountAOut / 2,
            amountBOut,
            1,
            1,
            msg.sender,
            block.timestamp + 1
        );

        if (address(_tokenA) != router.WETH()) {
            _tokenA.safeTransfer(msg.sender, _tokenA.balanceOf(address(this)));
        } else {
            IWETH(router.WETH()).withdraw(_tokenA.balanceOf(address(this)));
        }

        if (address(_tokenB) != router.WETH()) {
            _tokenB.safeTransfer(msg.sender, _tokenB.balanceOf(address(this)));
        } else {
            IWETH(router.WETH()).withdraw(_tokenB.balanceOf(address(this)));
        }

        emit IngredientsAdded(
            msg.sender,
            address(_tokenA),
            address(_tokenB),
            amountAOut / 2,
            amountBOut
        );

        return (addedAmountA, addedAmountB, liquidity);
    }

    /**
     * @dev Adds liquidity to a UniswapV2 Liquidity Pool
     * @param _lpToken The address of the UniswapV2 Liquidity Pool
     * @param _tokenA One of two address of the token pair of the LP
     * @param _tokenA One of two address of the token pair of the LP
     * @param _amountA Amount of the `_tokenA` to be added in the liquidity pool
     * @param _amountB Amount of the `_tokenB` to be added in the liquidity pool
     * @param _preparationDeadline Maximum amount of time to add the liquidity
     * @return The amount of UniswapV2 LP Tokens after add liquidity to the pool
     *
     * Emits a {IngredientsAdded} event.
     */
    function _addIngredients(
        address _lpToken,
        address _tokenA,
        address _tokenB,
        uint256 _amountA,
        uint256 _amountB,
        address _to,
        uint256 _preparationDeadline
    ) internal returns (uint256) {
        require(
            _tokenA != _tokenB,
            "ChocoMasterChef: You need more ingredients, no just one"
        );
        require(
            _tokenA != address(0) && _tokenB != address(0),
            "ChocoMasterChef: No ingredients"
        );
        require(
            poolInfoIndex[_lpToken] > 0,
            "ChocoMasterChef: Oups! Bad ingredient for Choco recipe"
        );
        require(
            (_amountA > 0 && _amountB > 0) ||
                (_amountA > 0 && _amountB == 0) ||
                (_amountA == 0 && _amountB > 0),
            "ChocoMasterChef: No enough ingredients"
        );
        require(
            _preparationDeadline > block.timestamp,
            "ChocoMasterChef: Sorry, the choco was already melted"
        );

        IWETH weth = IWETH(router.WETH());

        if (_amountA > 0 && _amountB == 0) {
            uint256 amountOut = _swap(_lpToken, _tokenA, _tokenB, _amountA / 2);
            _amountA = _amountA / 2;
            _amountB = amountOut;
            if (_tokenA != address(weth)) {
                IERC20(_tokenA).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _amountA
                );
            } else {
                weth.deposit{value: _amountA}();
            }
        } else if (_amountB > 0 && _amountA == 0) {
            uint256 amountOut = _swap(_lpToken, _tokenB, _tokenA, _amountB / 2);
            _amountB = _amountB / 2;
            _amountA = amountOut;
            if (_tokenB != address(weth)) {
                IERC20(_tokenB).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _amountB
                );
            } else {
                weth.deposit{value: _amountB}();
            }
        } else {
            if (_tokenA == address(weth)) {
                weth.deposit{value: _amountA}();
            }
            if (_tokenB == address(weth)) {
                weth.deposit{value: _amountB}();
            }
            if (_tokenA != address(weth)) {
                IERC20(_tokenA).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _amountA
                );
            }
            if (_tokenB != address(weth)) {
                IERC20(_tokenB).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _amountB
                );
            }
        }

        IERC20(_tokenA).safeApprove(address(router), _amountA);
        IERC20(_tokenB).safeApprove(address(router), _amountB);

        (uint256 addedAmountA, uint256 addedAmountB, uint256 liquidity) = router
        .addLiquidity(
            _tokenA,
            _tokenB,
            _amountA,
            _amountB,
            1,
            1,
            _to,
            _preparationDeadline
        );

        if (_amountA - addedAmountA > 0) {
            if (_tokenA != address(weth)) {
                IERC20(_tokenA).safeTransfer(
                    msg.sender,
                    _amountA - addedAmountA
                );
            } else {
                weth.withdraw(_amountA - addedAmountA);
                msg.sender.transfer(_amountA - addedAmountA);
            }
        }
        if (_amountB - addedAmountB > 0) {
            if (_tokenB != address(weth)) {
                IERC20(_tokenB).safeTransfer(
                    msg.sender,
                    _amountB - addedAmountB
                );
            } else {
                weth.withdraw(_amountB - addedAmountB);
                msg.sender.transfer(_amountB - addedAmountB);
            }
        }

        emit IngredientsAdded(msg.sender, _tokenA, _tokenB, _amountA, _amountB);

        return liquidity;
    }

    /**
     * @notice Allows to prepare Choco by placing ingredients into the ChocoMasterChef
     * @dev see {_prepareChoco}
     * @param lpToken The address of the Choco Pot
     * @param amount Amount of Choco to be prepared
     *
     * Emits a {ChocoPrepared} event.
     */
    function prepareChoco(address lpToken, uint256 amount) external {
        _prepareChoco(lpToken, amount, msg.sender);
    }

    /**
     * @dev Allows to stake UniswapV2 Liquidity Pool Tokens into the ChocoMasterChef
     * @param lpToken The address of UniswapV2 Liquidity Pool
     * @param amount Amount of UniswapV2 Liquidity Pool tokens
     * @param from Address of who is calling the function
     *
     * Emits a {ChocoPrepared} event.
     */
    function _prepareChoco(
        address lpToken,
        uint256 amount,
        address from
    ) internal {
        uint256 _pid = poolInfoIndex[lpToken];
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (from != address(this)) {
            pool.lpToken.safeTransferFrom(msg.sender, address(this), amount);
        }
        user.amount = user.amount.add(amount);
        user.rewardDebt = user.amount.mul(pool.accChocoPerShare).div(1e12);
        emit ChocoPrepared(msg.sender, lpToken, amount);
    }

    /**
     * @notice Add ingredients to a Choco Pot and start preparing
     * @dev Allows to add liquidity and to stake UniswapV2 Liquidity Pool Tokens
     * @dev into the ChocoMasterChef in a function
     * @dev Also, you can see {_addIngredients} and {_prepareChoco} for more details
     * @param lpToken The address of the Choco Pot
     * @param tokenA Address of the tokenA ingredient to be added to the Choco Pot
     * @param tokenB Address of the tokenB ingredient to be added to the Choco Pot
     * @param amountA Amount of the `tokenA` ingredient to be added
     * @param amountB Amount of the `tokenB` ingredient to be added
     * @param preparationDeadline Maximum amount of time to add the ingredients
     * @return The amount of UniswapV2 LP Tokens after add liquidity to the pool
     *
     * Emits {IngredientsAdded} and {ChocoPrepared} event.
     */
    function addIngredientsAndPrepareChoco(
        address lpToken,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 preparationDeadline
    ) external payable returns (uint256) {
        uint256 liquidity = _addIngredients(
            lpToken,
            tokenA,
            tokenB,
            amountA,
            amountB,
            address(this),
            preparationDeadline
        );
        _prepareChoco(lpToken, liquidity, address(this));

        emit IngredientsAdded(msg.sender, tokenA, tokenB, amountA, amountB);
        emit ChocoPrepared(msg.sender, lpToken, liquidity);

        return liquidity;
    }

    /**
     * @notice Claims the Choco Tokens rewards for placing ingredients and
     * @notice prepare Choco in the contract
     * @param lpToken The address of UniswapV2 Liquidity Pool
     * @param withdrawLPTokens If true, withdraw your UniswapV2 LP Tokens
     *
     * Emits a {ChocoClaimed} event.
     */
    function claimChoco(address lpToken, bool withdrawLPTokens) external {
        uint256 _pid = poolInfoIndex[lpToken];
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 reward = user.amount.mul(pool.accChocoPerShare).div(1e12).sub(
            user.rewardDebt
        );
        safeChocoTransfer(msg.sender, reward);
        if (withdrawLPTokens) {
            pool.lpToken.safeTransfer(address(msg.sender), user.amount);
            user.amount = 0;
        }
        user.rewardDebt = 0;
        emit ChocoClaimed(msg.sender, _pid, reward);
    }

    /**
     * @notice Get multiplier for Choco Token reward
     * @param from Last block rewarded given a pool
     * @param to Current block by `block.number`
     */
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

    /**
     * @notice Updates the reward values of a pool
     * @param _pid Index of a UniswapV2 Liquidity Pool
     */
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
        uint256 chocoReward = getMultiplier(pool.lastRewardBlock, block.number)
        .mul(chocoPerBlock)
        .mul(pool.allocPoint)
        .div(totalAllocPoint);
        choco.mint(address(this), chocoReward);
        pool.accChocoPerShare = pool.accChocoPerShare.add(
            chocoReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    /**
     * @dev Transfer safely Choco Token
     * @param _to Address to be transferred the Choco Tokens
     * @param _amount Amount of Choco Tokens to be transferred
     */
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
