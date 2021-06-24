const { ecsign } = require("ethereumjs-util");
const { hexlify } = require("ethers-utils");
const { keccak256, toUtf8Bytes, solidityPack } = require("ethers-utils");
const { web3 } = require("hardhat");
const { time } = require("@openzeppelin/test-helpers");

const PERMIT_TYPEHASH = keccak256(
  toUtf8Bytes(
    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
  )
);

function getDomainSeparator(name, tokenAddress) {
  return keccak256(
    web3.eth.abi.encodeParameters(
      ["bytes32", "bytes32", "bytes32", "uint256", "address"],
      [
        keccak256(
          toUtf8Bytes(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
          )
        ),
        keccak256(toUtf8Bytes(name)),
        keccak256(toUtf8Bytes("1")),
        1,
        tokenAddress,
      ]
    )
  );
}

const getApprovalDigest = async (
  token,
  owner,
  spender,
  value,
  nonce,
  deadline
) => {
  const name = await token.name();
  const DOMAIN_SEPARATOR = getDomainSeparator(name, token.address);
  return keccak256(
    solidityPack(
      ["bytes1", "bytes1", "bytes32", "bytes32"],
      [
        "0x19",
        "0x01",
        DOMAIN_SEPARATOR,
        keccak256(
          web3.eth.abi.encodeParameters(
            ["bytes32", "address", "address", "uint256", "uint256", "uint256"],
            [PERMIT_TYPEHASH, owner, spender, value, nonce, deadline]
          )
        ),
      ]
    )
  );
};

const signTokenPermit = async (token, sender, senderPk, spender, value) => {
  const nonce = await token.nonces(sender);
  const deadline = (await time.latest()) + 1;
  const digest = await getApprovalDigest(
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
    r: hexlify(r),
    s: hexlify(s),
  };
};

module.exports = {
  getApprovalDigest,
  signTokenPermit,
};
