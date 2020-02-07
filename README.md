# Peer Loaning Mediation Framework

Stack:

Solidity contract <-> truffle <-> ganache <-> MetaMask <-> web3.js <-> App interface <-> browser <-> localhost <-> http-server

## Setup:

### Solidity Contract:

To setup, the contract needs only to be compiled. See slides and comments on exactly how to use the contract.

The only contract that will function correctly with the webapp included is the Demo version with extra functionality for testing and demonstration. Be careful just wantonly throwing the non-demo version on an actual blockchain, I highly suggest testing everything out with the Demo version before trying to use.

### Truffle Compilation Instructions:

I used Truffle for my compiler and migration to the test chain. To install truffle via npm, use:

`npm install truffle -g`

You can find more info about truffle here: https://www.trufflesuite.com/truffle

Once you have truffle installed, just use:

`truffle compile --all`

to recompile the files.

### Ganache Testing Blockchain

Ganache is a test blockchain GUI that I used to power my manual testing. You can get it here https://www.trufflesuite.com/ganache

Once you have a new workspace running, switch the port it uses to 7545 from 8545 (the default) and NetworkID to 5777 to match the migrations and config files included. Then you can add the truffle config file to the projects in Ganache and deploy the contract using

`truffle migrate --reset`

After that you will be able to see it in the Contracts tab and if you did everything correctly, it will have an address.

### MetaMask

Next you will have to install the MetaMask extension from your browser and add your Ganache chain as a custom RPC server. Then you should add some accounts from your Ganache net using their private key and check that it shows a balance in those accounts. You can find MetaMask here:

https://metamask.io/

### Web3.js

I don't think you should need to do anything here, but if anything complains about not having web3.js dependencies, you can install them via npm by the instructions here (add the -g tag to install globally and not have to worry about where you're installing):

https://web3js.readthedocs.io/en/v1.2.4/getting-started.html

### http-server

This is just a cli for hosting the webapp. Install using npm via:

`npm install http-server -g`

and run it in the demoapp directory. This will allow your browser to access it at http://localhost:8080/demoapp.html

### Using the App interface

To get the webapp to work, you will have to edit the file to give it the address of the contract on your Ganache network (which is generated randomly) manually.

The Demo version of the contract comes with these hardcoded initial values:

```
lenderCollateral = 10 ether;
renterCollateral = 20 ether;
paymentAmount = 1 ether;
rentPeriod = 20;
deadline = 40;
graceTime = 2;
```

Feel free to change them, they will only effect your testing flow, any non-zero value that respects renterCollateral > lenderCollateral > paymentAmount, gracetime < 1/5\*rentPeriod, and deadline > rentPeriod should work.

You might want to uncomment the block of HTML text after

`Look at the internal public variables:`

to be able to see more of the internal workings and understand why you are unable to do certain actions. Additionally, if you check the Log tab in Ganache, you will see the messages when you fail a "require()" clause when using one of the contract functions.

You don't need to redeploy the contract when you finish, the RESET button will return the contract to the initial state. To prenvent accidentally messing up and locking ether in the contract, the contract balance is not reset so after using the RESET button, you can use abortNoInterest() to get out any ether back to the Lender.

Feel free to contact me with any questions.

### analysis

This folder contains an attempt to set up a learning model on the decision tree of the contract. However rules based learning is very slow so currently it doesn't have complete success and holds a number of hard coded parameters. This is in a jupyter notebook which you can learn how to setup here https://jupyter.org/
