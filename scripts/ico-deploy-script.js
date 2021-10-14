// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const AffynToken = await hre.ethers.getContractFactory("AffynToken");
  const affynToken = await AffynToken.deploy('AffynToken', 'ATT', '1000000000000');

  await affynToken.deployed();

  console.log("affynToken deployed to:", affynToken.address);

  const IcoSale = await hre.ethers.getContractFactory("TSTokenPrivateSale");

  var openingTime = Math.round(Date.now()/1000) + 60; //In 1 minute
  var closingTime = openingTime + 3600; //In an hour

  const icoSale = await IcoSale.deploy(affynToken.address, '2200000000000000000000000', '500000000000000000000000', openingTime, closingTime, 
  '0xDB580ea4595Efb66507926cAcb09f9a80F0A5148', '1',  '3600', '604800', '86400');

  await icoSale.deployed();
  console.log("\nicoSale deployed to:", icoSale.address);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
