const { assert, upgrades, ethers } = require("hardhat");
const { time } = require("@openzeppelin/test-helpers");

const toWei = (value, type) => web3.utils.toWei(String(value), type);

contract("ChocoMasterChef (Proxy)", ([admin]) => {
  let chocoChef, chocoToken, adminSigner, proxyAdmin, startBlock;

  before(async () => {
    adminSigner = await ethers.getSigner(admin);

    const ChocoToken = await ethers.getContractFactory(
      "ChocoToken",
      adminSigner
    );
    chocoToken = await ChocoToken.deploy();
    await chocoToken.deployed();

    chocoChef = await ethers.getContractFactory("ChocoMasterChef", adminSigner);
    startBlock = Number(await time.latestBlock());
    instance = await upgrades.deployProxy(chocoChef, [
      chocoToken.address,
      toWei(25),
      startBlock,
    ]);

    proxyAdmin = await upgrades.admin.getInstance();
  });

  it("contract should initialize", async () => {
    assert.equal(toWei(25), await instance.chocoPerBlock());
    assert.equal(startBlock, Number(await instance.startBlock()));
  });

  it("proxy admin should be the admin signer", async () => {
    assert.equal(admin, await proxyAdmin.owner());
  });
});
