import { network } from "hardhat";

const { viem } = await network.connect();

const publicClient = await viem.getPublicClient();
const [senderClient] = await viem.getWalletClients();

const implContract = await viem.getContractAt("ImplementationDeployer", "0x23de5C588e24a1B668852625bab1B5dC72343018") ;

const latestBlock = await publicClient.getBlockNumber();
const fromBlock = latestBlock - 200n;

console.log(latestBlock);

const implEvents = await publicClient.getContractEvents({
    address: implContract.address,
    abi: implContract.abi,
    eventName: "ImplementationDeployed",
    fromBlock,
    strict: true,
});

const factoryEvents = await publicClient.getContractEvents({
    address: implContract.address,
    abi: implContract.abi,
    eventName: "FactoryDeployed",
    fromBlock,
    strict: true,
});

console.log("implEvents:", implEvents);
console.log("factoryEvents:", factoryEvents);