const { web3, ethers } = require("hardhat");
const { ecsign } = require("ethereumjs-util");

const ERC20PERMIT_TYPEHASH = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes(
    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
  )
);

const DAIPERMIT_TYPEHASH = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes(
    "Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)"
  )
);

function getDomainSeparator(name, tokenAddress) {
  return ethers.utils.keccak256(
    web3.eth.abi.encodeParameters(
      ["bytes32", "bytes32", "bytes32", "uint256", "address"],
      [
        ethers.utils.keccak256(
          ethers.utils.toUtf8Bytes(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
          )
        ),
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes(name)),
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("1")),
        1,
        tokenAddress,
      ]
    )
  );
}

const getERC20PermitApprovalDigest = async (
  token,
  owner,
  spender,
  value,
  nonce,
  deadline
) => {
  const name = await token.name();
  const DOMAIN_SEPARATOR = getDomainSeparator(name, token.address);
  return ethers.utils.keccak256(
    ethers.utils.solidityPack(
      ["bytes1", "bytes1", "bytes32", "bytes32"],
      [
        "0x19",
        "0x01",
        DOMAIN_SEPARATOR,
        ethers.utils.keccak256(
          web3.eth.abi.encodeParameters(
            ["bytes32", "address", "address", "uint256", "uint256", "uint256"],
            [ERC20PERMIT_TYPEHASH, owner, spender, value, nonce, deadline]
          )
        ),
      ]
    )
  );
};

const getDAIApprovalDigest = async (
  token,
  holder,
  spender,
  nonce,
  deadline,
  allowed
) => {
  const name = await token.name();
  const DOMAIN_SEPARATOR = getDomainSeparator(name, token.address);
  return ethers.utils.keccak256(
    ethers.utils.solidityPack(
      ["bytes1", "bytes1", "bytes32", "bytes32"],
      [
        "0x19",
        "0x01",
        DOMAIN_SEPARATOR,
        ethers.utils.keccak256(
          web3.eth.abi.encodeParameters(
            ["bytes32", "address", "address", "uint256", "uint256", "bool"],
            [DAIPERMIT_TYPEHASH, holder, spender, nonce, deadline, allowed]
          )
        ),
      ]
    )
  );
};

const signERC20PermitToken = async (token, sender, senderPk, spender, value, deadline) => {
  const nonce = await token.nonces(sender);
  const digest = await getERC20PermitApprovalDigest(
    token,
    sender,
    spender,
    value,
    nonce,
    deadline
  );

  const { v, r, s } = ecsign(
    Buffer.from(digest.slice(2), "hex"),
    Buffer.from(senderPk.slice(2), "hex")
  );

  return {
    deadline,
    v,
    r: ethers.utils.hexlify(r),
    s: ethers.utils.hexlify(s),
  };
};

const signDAIToken = async (token, holder, holderPk, spender, expiry, allowed) => {
  const nonce = await token.nonces(holder);
  const digest = await getDAIApprovalDigest(
    token,
    holder,
    spender,
    nonce,
    expiry,
    allowed
  );

  const { v, r, s } = ecsign(
    Buffer.from(digest.slice(2), "hex"),
    Buffer.from(holderPk.slice(2), "hex")
  );

  return {
    allowed,
    nonce,
    expiry,
    v,
    r: ethers.utils.hexlify(r),
    s: ethers.utils.hexlify(s),
  };
};

module.exports = {
  getERC20PermitApprovalDigest,
  getDAIApprovalDigest,
  signERC20PermitToken,
  signDAIToken
};
