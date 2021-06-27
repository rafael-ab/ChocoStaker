const ChocoMasterChef = artifacts.require("ChocoMasterChef");
const ChocoToken = artifacts.require("ChocoToken");
const IERC20 = artifacts.require(
  "@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20"
);
const IUniV2ERC20 = artifacts.require("IUniswapV2ERC20");
const { assert, web3, network } = require("hardhat");
const {
  expectEvent,
  expectRevert,
  time,
} = require("@openzeppelin/test-helpers");

// message signer tools
const { signTokenPermit } = require("./utils/signerUtils");

// Token Address
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const LINK_ADDRESS = "0x514910771AF9Ca656af840dff83E8264EcF986CA";
const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const USDT_ADDRESS = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
const TUSD_ADDRESS = "0x0000000000085d4780B73119b644AE5ecd22b376";
const BUSD_ADDRESS = "0x4Fabb145d64652a948d72533023f6E7A623C7C53";
const BAT_ADDRESS = "0x0D8775F648430679A709E98d2b0Cb6250d2887EF";

// Account Address
const ADMIN = "0xbe6977e08d4479c0a6777539ae0e8fa27be4e9d6";
const PLAYER1 = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"; // Hardhat Account 0
const PLAYER1_PK =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const PLAYER2 = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"; // Hardhat Account 1
const PLAYER2_PK =
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
const PLAYER3 = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"; // Hardhat Account 2
const PLAYER3_PK =
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a";
const PLAYER_WITH_DAI = "0xC2C5A77d9f434F424Df3d39de9e90d95A0Df5Aca"; // Account with DAI
const PLAYER_WITH_USDT = "0xB78e90E2eC737a2C0A24d68a0e54B410FFF3bD6B"; // Account with USDT
const PLAYER_WITH_USDC = "0x62Fe3E658139E1b38b8BAE6013C26E5465A2A743"; // Account with USDT and USDC

// Uniswap LP Tokens
const LP_DAI_ETH = "0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11";
const LP_DAI_USDC = "0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5";
const LP_USDC_ETH = "0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc";
const LP_USDT_ETH = "0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852";
const LP_TUSD_ETH = "0xb4d0d9df2738abE81b87b66c80851292492D1404";
const LP_BAT_ETH = "0xB6909B960DbbE7392D405429eB2b3649752b4838";
const LP_LINK_ETH = "0xa2107FA5B38d9bbd2C461D6EDf11B11A50F6b974";

// Helpers
const toWei = (value, type) => web3.utils.toWei(String(value), type);
const fromWei = (value, type) =>
  Number(web3.utils.fromWei(String(value), type));
const toBN = (value) => web3.utils.toBN(String(value));

contract("ChocoMasterChef", () => {
  let chocoChef, chocoToken;

  before(async () => {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [ADMIN],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [PLAYER_WITH_DAI],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [PLAYER_WITH_USDT],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [PLAYER_WITH_USDC],
    });

    const daiToken = await IERC20.at(DAI_ADDRESS);
    await daiToken.transfer(PLAYER1, toWei(50000), { from: PLAYER_WITH_DAI });
    await daiToken.transfer(PLAYER2, toWei(50000), { from: PLAYER_WITH_DAI });
    await daiToken.transfer(PLAYER3, toWei(50000), { from: PLAYER_WITH_DAI });

    const usdcToken = await IERC20.at(USDC_ADDRESS);
    await usdcToken.transfer(PLAYER1, 50000 * 10 ** 6, {
      from: PLAYER_WITH_USDC,
    });
    await usdcToken.transfer(PLAYER2, 50000 * 10 ** 6, {
      from: PLAYER_WITH_USDC,
    });
    await usdcToken.transfer(PLAYER3, 50000 * 10 ** 6, {
      from: PLAYER_WITH_USDC,
    });

    chocoToken = await ChocoToken.new({ from: ADMIN });

    chocoChef = await ChocoMasterChef.new({ from: ADMIN });
    await chocoChef.initialize(
      chocoToken.address,
      toWei(25),
      Number(await time.latestBlock()),
      { from: ADMIN }
    );

    // transfer ownership to ChocoMasterChef to reward users
    await chocoToken.transferOwnership(chocoChef.address, { from: ADMIN });

    await chocoChef.addChocoPot(120, LP_DAI_ETH, { from: ADMIN });
    await chocoChef.addChocoPot(60, LP_DAI_USDC, { from: ADMIN });
    await chocoChef.addChocoPot(30, LP_USDC_ETH, { from: ADMIN });
    await chocoChef.addChocoPot(10, LP_BAT_ETH, { from: ADMIN });
    await chocoChef.addChocoPot(25, LP_LINK_ETH, { from: ADMIN });
    await chocoChef.addChocoPot(80, LP_USDT_ETH, { from: ADMIN });
    await chocoChef.addChocoPot(40, LP_TUSD_ETH, { from: ADMIN });
  });

  it("player1 should add liquidity to DAI/ETH LP Token", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const timestamp = await time.latest();

    const daiToken = await IERC20.at(DAI_ADDRESS);
    await daiToken.approve(chocoChef.address, toWei(2500), {
      from: PLAYER1,
    });

    const tx = await chocoChef.addIngredients(
      LP_DAI_ETH,
      WETH_ADDRESS,
      DAI_ADDRESS,
      toWei(2),
      toWei(2500),
      timestamp + 1,
      { from: PLAYER1, value: toWei(2) }
    );

    await expectEvent(tx, "IngredientsAdded", {
      user: PLAYER1,
      tokenA: WETH_ADDRESS,
      tokenB: DAI_ADDRESS,
      amountA: toWei(2),
      amountB: toWei(2500),
    });

    const daiETHLPToken = await IERC20.at(LP_DAI_ETH);
    const balancePlayer1 = await daiETHLPToken.balanceOf(PLAYER1);
    console.log(
      "\tPLAYER1 LP Tokens :>> ",
      (Number(balancePlayer1) / 10 ** 18).toFixed(18)
    );
    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player1 should add liquidity to DAI/ETH LP Token only with DAI", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const timestamp = await time.latest();

    const daiToken = await IERC20.at(DAI_ADDRESS);
    await daiToken.approve(chocoChef.address, toWei(2500), {
      from: PLAYER1,
    });

    const tx = await chocoChef.addIngredients(
      LP_DAI_ETH,
      WETH_ADDRESS,
      DAI_ADDRESS,
      0,
      toWei(2500),
      timestamp + 1,
      { from: PLAYER1, value: 0 }
    );

    /* await expectEvent(tx, "IngredientsAdded", {
      user: PLAYER1,
      tokenA: WETH_ADDRESS,
      tokenB: DAI_ADDRESS,
      amountA: toWei(2),
      amountB: toWei(2500),
    }); */

    const daiETHLPToken = await IERC20.at(LP_DAI_ETH);
    const balancePlayer1 = await daiETHLPToken.balanceOf(PLAYER1);
    console.log(
      "\tPLAYER1 LP Tokens :>> ",
      (Number(balancePlayer1) / 10 ** 18).toFixed(18)
    );
    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player1 should add liquidity to DAI/ETH LP Token only with ETH", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const timestamp = await time.latest();

    const tx = await chocoChef.addIngredients(
      LP_DAI_ETH,
      WETH_ADDRESS,
      DAI_ADDRESS,
      toWei(1),
      0,
      timestamp + 1,
      { from: PLAYER1, value: toWei(1) }
    );

    /* await expectEvent(tx, "IngredientsAdded", {
      user: PLAYER1,
      tokenA: WETH_ADDRESS,
      tokenB: DAI_ADDRESS,
      amountA: toWei(2),
      amountB: toWei(2500),
    }); */

    const daiETHLPToken = await IERC20.at(LP_DAI_ETH);
    const balancePlayer1 = await daiETHLPToken.balanceOf(PLAYER1);
    console.log(
      "\tPLAYER1 LP Tokens :>> ",
      (Number(balancePlayer1) / 10 ** 18).toFixed(18)
    );
    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player2 should add liquidity to DAI/ETH LP Token", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const timestamp = await time.latest();

    const daiToken = await IERC20.at(DAI_ADDRESS);
    await daiToken.approve(chocoChef.address, toWei(500), {
      from: PLAYER2,
    });

    const tx = await chocoChef.addIngredients(
      LP_DAI_ETH,
      WETH_ADDRESS,
      DAI_ADDRESS,
      toWei(1),
      toWei(500),
      timestamp + 1,
      { from: PLAYER2, value: toWei(1) }
    );

    await expectEvent(tx, "IngredientsAdded", {
      user: PLAYER2,
      tokenA: WETH_ADDRESS,
      tokenB: DAI_ADDRESS,
      amountA: toWei(1),
      amountB: toWei(500),
    });

    const daiETHLPToken = await IERC20.at(LP_DAI_ETH);
    const balancePlayer2 = await daiETHLPToken.balanceOf(PLAYER2);
    console.log(
      "\tPLAYER2 LP Tokens :>> ",
      (Number(balancePlayer2) / 10 ** 18).toFixed(18)
    );
    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player2 should add liquidity to DAI/USDC LP Token", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const timestamp = await time.latest();

    const daiToken = await IERC20.at(DAI_ADDRESS);
    await daiToken.approve(chocoChef.address, toWei(500), {
      from: PLAYER2,
    });

    const usdcToken = await IERC20.at(USDC_ADDRESS);
    await usdcToken.approve(chocoChef.address, 500 * 10 ** 6, {
      from: PLAYER2,
    });

    const tx = await chocoChef.addIngredients(
      LP_DAI_USDC,
      DAI_ADDRESS,
      USDC_ADDRESS,
      toWei(500),
      500 * 10 ** 6,
      timestamp + 1,
      { from: PLAYER2 }
    );

    await expectEvent(tx, "IngredientsAdded", {
      user: PLAYER2,
      tokenA: DAI_ADDRESS,
      tokenB: USDC_ADDRESS,
      amountA: toWei(500),
      amountB: toBN(500 * 10 ** 6),
    });

    const daiUSDCLPToken = await IERC20.at(LP_DAI_USDC);
    const balancePlayer2 = await daiUSDCLPToken.balanceOf(PLAYER2);
    console.log(
      "\tPLAYER2 LP Tokens :>> ",
      (Number(balancePlayer2) / 10 ** 18).toFixed(18)
    );
    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player1 should add liquidity to DAI/USDC LP Token with only DAI", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const timestamp = await time.latest();

    const daiToken = await IERC20.at(DAI_ADDRESS);
    await daiToken.approve(chocoChef.address, toWei(500), {
      from: PLAYER1,
    });

    const tx = await chocoChef.addIngredients(
      LP_DAI_USDC,
      DAI_ADDRESS,
      USDC_ADDRESS,
      toWei(500),
      0,
      timestamp + 1,
      { from: PLAYER1 }
    );

    /* await expectEvent(tx, "IngredientsAdded", {
      user: PLAYER1,
      tokenA: DAI_ADDRESS,
      tokenB: USDC_ADDRESS,
      amountA: toWei(250),
      amountB: toBN(0),
    }); */

    const daiUSDCLPToken = await IERC20.at(LP_DAI_USDC);
    const balancePlayer1 = await daiUSDCLPToken.balanceOf(PLAYER1);
    console.log(
      "\tPLAYER1 LP Tokens :>> ",
      (Number(balancePlayer1) / 10 ** 18).toFixed(18)
    );
    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player1 should stake his DAI-ETH LP tokens using approve", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const daiLPToken = await IUniV2ERC20.at(LP_DAI_ETH);
    const balancePlayer1 = await daiLPToken.balanceOf(PLAYER1);
    await daiLPToken.approve(chocoChef.address, balancePlayer1, {
      from: PLAYER1,
    });

    const balancePlayer1Before = await daiLPToken.balanceOf(PLAYER1);
    console.log(
      "\tPLAYER1 LP Tokens \t\t(Before) :>> ",
      (Number(balancePlayer1Before) / 10 ** 18).toFixed(18)
    );
    const balanceChocoChefBefore = await daiLPToken.balanceOf(
      chocoChef.address
    );
    console.log(
      "\tChocoMasterChef LP Tokens \t(Before) :>> ",
      (Number(balanceChocoChefBefore) / 10 ** 18).toFixed(18)
    );

    const tx = await chocoChef.prepareChoco(LP_DAI_ETH, balancePlayer1, {
      from: PLAYER1,
    });

    const balancePlayer1After = await daiLPToken.balanceOf(PLAYER1);
    console.log(
      "\tPLAYER1 LP Tokens \t\t(After) :>> ",
      (Number(balancePlayer1After) / 10 ** 18).toFixed(18)
    );
    const balanceChocoChefAfter = await daiLPToken.balanceOf(chocoChef.address);
    console.log(
      "\tChocoMasterChef LP Tokens \t(After) :>> ",
      (Number(balanceChocoChefAfter) / 10 ** 18).toFixed(18)
    );

    await expectEvent(tx, "ChocoPrepared", {
      user: PLAYER1,
      lpToken: LP_DAI_ETH,
      amount: balancePlayer1,
    });

    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player2 should stake his DAI-ETH LP tokens using permit", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const daiLPToken = await IUniV2ERC20.at(LP_DAI_ETH);
    const balancePlayer2 = await daiLPToken.balanceOf(PLAYER2);

    // signing data
    const result = await signTokenPermit(
      daiLPToken,
      PLAYER2,
      PLAYER2_PK,
      chocoChef.address,
      balancePlayer2
    );

    await daiLPToken.permit(
      PLAYER2,
      chocoChef.address,
      balancePlayer2,
      result.deadline,
      result.v,
      result.r,
      result.s
    );

    const balancePlayer2Before = await daiLPToken.balanceOf(PLAYER2);
    console.log(
      "\tPLAYER2 LP Tokens \t\t(Before) :>> ",
      (Number(balancePlayer2Before) / 10 ** 18).toFixed(18)
    );
    const balanceChocoChefBefore = await daiLPToken.balanceOf(
      chocoChef.address
    );
    console.log(
      "\tChocoMasterChef LP Tokens \t(Before) :>> ",
      (Number(balanceChocoChefBefore) / 10 ** 18).toFixed(18)
    );

    const tx = await chocoChef.prepareChoco(LP_DAI_ETH, balancePlayer2, {
      from: PLAYER2,
    });

    const balancePlayer2After = await daiLPToken.balanceOf(PLAYER2);
    console.log(
      "\tPLAYER2 LP Tokens \t\t(After) :>> ",
      (Number(balancePlayer2After) / 10 ** 18).toFixed(18)
    );
    const balanceChocoChefAfter = await daiLPToken.balanceOf(chocoChef.address);
    console.log(
      "\tChocoMasterChef LP Tokens \t(After) :>> ",
      (Number(balanceChocoChefAfter) / 10 ** 18).toFixed(18)
    );

    await expectEvent(tx, "ChocoPrepared", {
      user: PLAYER2,
      lpToken: LP_DAI_ETH,
      amount: balancePlayer2,
    });

    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player3 should add liquidity and stake his DAI-ETH LP tokens in one transaction", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const timestamp = await time.latest();

    const daiToken = await IERC20.at(DAI_ADDRESS);
    await daiToken.approve(chocoChef.address, toWei(1500), { from: PLAYER3 });

    const daiLPToken = await IERC20.at(LP_DAI_ETH);

    const balanceChocoChefBefore = await daiLPToken.balanceOf(
      chocoChef.address
    );
    console.log(
      "\tChocoMasterChef LP Tokens \t(Before) :>> ",
      (Number(balanceChocoChefBefore) / 10 ** 18).toFixed(18)
    );

    const tx = await chocoChef.addIngredientsAndPrepareChoco(
      LP_DAI_ETH,
      WETH_ADDRESS,
      DAI_ADDRESS,
      toWei(1),
      toWei(1500),
      timestamp + 1,
      { from: PLAYER3, value: toWei(1) }
    );

    const balanceChocoChefAfter = await daiLPToken.balanceOf(chocoChef.address);
    console.log(
      "\tChocoMasterChef LP Tokens \t(After) :>> ",
      (Number(balanceChocoChefAfter) / 10 ** 18).toFixed(18)
    );

    await expectEvent(tx, "IngredientsAdded", {
      user: PLAYER3,
      tokenA: WETH_ADDRESS,
      tokenB: DAI_ADDRESS,
      amountA: toWei(1),
      amountB: toWei(1500),
    });

    /* await expectEvent(tx, "ChocoPrepared", {
      user: PLAYER3,
      token: LP_DAI_ETH,
      amount: balancePlayer2, // TODO: how to get the liquidity
    }); */

    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player3 should add liquidity and stake his USDT-ETH LP tokens in one transaction", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const timestamp = await time.latest();

    /* const daiToken = await IERC20.at(DAI_ADDRESS);
    await daiToken.approve(chocoChef.address, toWei(1500), { from: PLAYER3 }); */

    const usdtLPToken = await IERC20.at(LP_USDT_ETH);

    const balanceChocoChefBefore = await usdtLPToken.balanceOf(
      chocoChef.address
    );
    console.log(
      "\tChocoMasterChef LP Tokens \t(Before) :>> ",
      (Number(balanceChocoChefBefore) / 10 ** 18).toFixed(18)
    );

    const tx = await chocoChef.addIngredientsAndPrepareChoco(
      LP_USDT_ETH,
      WETH_ADDRESS,
      USDT_ADDRESS,
      toWei(1),
      0,
      timestamp + 1,
      { from: PLAYER3, value: toWei(1) }
    );

    const balanceChocoChefAfter = await usdtLPToken.balanceOf(chocoChef.address);
    console.log(
      "\tChocoMasterChef LP Tokens \t(After) :>> ",
      (Number(balanceChocoChefAfter) / 10 ** 18).toFixed(18)
    );

    /* await expectEvent(tx, "IngredientsAdded", {
      user: PLAYER3,
      tokenA: WETH_ADDRESS,
      tokenB: DAI_ADDRESS,
      amountA: toWei(1),
      amountB: toWei(1500),
    }); */

    /* await expectEvent(tx, "ChocoPrepared", {
      user: PLAYER3,
      token: LP_DAI_ETH,
      amount: balancePlayer2, // TODO: how to get the liquidity
    }); */

    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player1 should claim rewards y get back DAI-ETH LP Tokens", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const daiLPToken = await IERC20.at(LP_DAI_ETH);
    const balancePlayer1 = await daiLPToken.balanceOf(PLAYER1);

    const balancePlayer1Before = await chocoToken.balanceOf(PLAYER1);
    console.log(
      "\tPLAYER1 Choco Tokens \t\t(Before) :>> ",
      (Number(balancePlayer1Before) / 10 ** 18).toFixed(18)
    );

    const tx = await chocoChef.claimChoco(LP_DAI_ETH, true, { from: PLAYER1 });

    const balancePlayer1After = await chocoToken.balanceOf(PLAYER1);
    console.log(
      "\tPLAYER1 Choco Tokens \t\t(After) :>> ",
      (Number(balancePlayer1After) / 10 ** 18).toFixed(18)
    );

    /* await expectEvent(tx, "ChocoPrepared", {
      user: PLAYER1,
      lpToken: LP_DAI,
      amount: balancePlayer1,
    }); */

    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });

  it("player2 should claim only rewards", async () => {
    console.log(
      "    ------------------------------------------------------------------"
    );

    const daiLPToken = await IERC20.at(LP_DAI_ETH);
    const balancePlayer2 = await daiLPToken.balanceOf(PLAYER2);

    const balancePlayer2Before = await chocoToken.balanceOf(PLAYER2);
    console.log(
      "\tPLAYER2 Choco Tokens \t\t(Before) :>> ",
      (Number(balancePlayer2Before) / 10 ** 18).toFixed(18)
    );

    const tx = await chocoChef.claimChoco(LP_DAI_ETH, false, { from: PLAYER2 });

    const balancePlayer2After = await chocoToken.balanceOf(PLAYER2);
    console.log(
      "\tPLAYER2 Choco Tokens \t\t(After) :>> ",
      (Number(balancePlayer2After) / 10 ** 18).toFixed(18)
    );

    /* await expectEvent(tx, "ChocoPrepared", {
      user: PLAYER2,
      lpToken: LP_DAI_ETH,
      amount: balancePlayer2,
    }); */

    console.log("\tGas Used :>> ", tx.receipt.gasUsed);
  });
});
