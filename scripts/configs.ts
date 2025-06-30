import { Hex, zeroAddress } from "viem";

export const protocolAddress = "0x1F4899e17F9eEc08B91a48f8A5be12Bca14F18a6" as Hex;

export const deployment_configs = {
    polygon_amoy: {
        link_router: "0x9C32fCB86BF0f4a1A8921a9Fe46de3198bb884B2" as Hex,
        link_token: "0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904" as Hex,
        linkusd_aggregator: "0xc2e2848e28B9fE430Ab44F55a8437a33802a219C" as Hex,
        protocol: protocolAddress,
        bridge: "0x7E60C904CdfcF25d7e7e8c245Ffce4B7d99E1D68" as Hex,
        chain_selector: "16281711391670634445",
        allowed_chainselectors: [
            {
                chain_id: 11155111,
                chain_selector: "16015286601757825753"
            },
            {
                chain_id: 421614,
                chain_selector: "3478487238524512106"
            },
            {
                chain_id: 43113,
                chain_selector: "14767482510784806043"
            }
        ], //sepolia, arb, avax
        pools: [
            {
                id: "100001",
                underlying_token: "0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582" as Hex,
                supply_token_name: "Bond USDC liquidity supply",
                supply_token_symbol: "USDC.bs"
            }
        ]
    },
    sepolia: {
        link_router: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59" as Hex,
        link_token: "0x779877A7B0D9E8603169DdbD7836e478b4624789" as Hex,
        linkusd_aggregator: "0xc59E3633BAAC79493d908e63626716e204A45EdF" as Hex,
        protocol: protocolAddress,
        bridge: "0x5e1c84B064a8232D735Bc3B3fd06fB1589ba1208" as Hex,
        chain_selector: "16015286601757825753",
        allowed_chainselectors: [
            {
                chain_id: 80002,
                chain_selector: "16281711391670634445"
            },
            {
                chain_id: 421614,
                chain_selector: "3478487238524512106"
            },
            {
                chain_id: 43113,
                chain_selector: "14767482510784806043"
            }
        ], //amoy, arb, avax
        pools: [
            {
                id: "100001",
                underlying_token: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" as Hex,
                supply_token_name: "Bond USDC liquidity supply",
                supply_token_symbol: "USDC.bs"
            }
        ]
    },
    arbitrum_sepolia: {
        link_router: "0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165" as Hex,
        link_token: "0xb1D4538B4571d411F07960EF2838Ce337FE1E80E" as Hex,
        linkusd_aggregator: "0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298" as Hex,
        protocol: protocolAddress,
        bridge: "0xEbae7530DEb9b106595025B1a4208354102B0867" as Hex,
        chain_selector: "3478487238524512106",
        allowed_chainselectors: [
            {
                chain_id: 11155111,
                chain_selector: "16015286601757825753"
            },
            {
                chain_id: 80002,
                chain_selector: "16281711391670634445"
            },
            {
                chain_id: 43113,
                chain_selector: "14767482510784806043"
            }
        ], //sepolia, amoy, avax
        pools: [
            {
                id: "100001",
                underlying_token: "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d" as Hex,
                supply_token_name: "Bond USDC liquidity supply",
                supply_token_symbol: "USDC.bs"
            }
        ]
    },
    avalanche_fuji: {
        link_router: "0xF694E193200268f9a4868e4Aa017A0118C9a8177" as Hex,
        link_token: "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846" as Hex,
        linkusd_aggregator: "0x34C4c526902d88a3Aa98DB8a9b802603EB1E3470" as Hex,
        protocol: protocolAddress,
        bridge: "0x8Bb975F66f5bBE04be7991D78BB7CB92E8250950" as Hex,
        chain_selector: "14767482510784806043",
        allowed_chainselectors: [
            {
                chain_id: 11155111,
                chain_selector: "16015286601757825753"
            }, 
            {
                chain_id: 421614,
                chain_selector: "3478487238524512106"
            },
            {
                chain_id: 80002,
                chain_selector: "16281711391670634445"
            }
        ], //sepolia, arb, amoy
        pools: [
            {
                id: "100001",
                underlying_token: "0x5425890298aed601595a70AB815c96711a31Bc65" as Hex,
                supply_token_name: "Bond USDC liquidity supply",
                supply_token_symbol: "USDC.bs"
            }
        ]
    },    
    local: {
        link_router: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59" as Hex,
        link_token: "0x779877A7B0D9E8603169DdbD7836e478b4624789" as Hex,
        linkusd_aggregator: zeroAddress,
        protocol: protocolAddress,
        bridge: "0x45e0851cf98E8f5Ba1FC02c6282B7f8c3c0f86FC" as Hex,
        chain_selector: "14767482510784806041",
        allowed_chainselectors: [
            {
                chain_id: 80002,
                chain_selector: "16281711391670634445"
            },
            {
                chain_id: 421614,
                chain_selector: "3478487238524512106"
            },
            {
                chain_id: 43113,
                chain_selector: "14767482510784806043"
            },
            {
                chain_id: 11155111,
                chain_selector: "16015286601757825753"
            }
        ], //amoy, arb, avax
        pools: [
            {
                id: "100001",
                underlying_token: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" as Hex,
                supply_token_name: "Bond USDC liquidity supply",
                supply_token_symbol: "USDC.bs"
            }
        ]
    },
}

export function getChainNameFromId(chianId: number) {
    switch (chianId) {
        case 80002:
            return "polygon_amoy"
            break;
        case 11155111:
            return "sepolia"
            break;
        case 421614:
            return "arbitrum_sepolia"
            break;
        case 43113:
            return "avalanche_fuji"
            break;
        default:
            return "local"
            break;
    }
}