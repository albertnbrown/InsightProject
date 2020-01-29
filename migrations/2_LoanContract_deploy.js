var Migrations = artifacts.require("./LoanContract.sol");

module.exports = function(deployer) {
  deployer.deploy(Migrations);
};