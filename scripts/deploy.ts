import hre, { ethers } from "hardhat";

async function main() {
  const constructorArgs: any[] = [
    "",
  ];
  const factory = await ethers.getContractFactory("SR");
  const contract = await factory.deploy(...constructorArgs);
  await contract.deployed();
  console.log("SR contract successfully deployed:", contract.address)
  await hre.run("verify:verify", {
    address: contract.address,
    constructorArguments: constructorArgs
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
