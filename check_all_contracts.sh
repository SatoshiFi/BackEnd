#!/bin/bash

RPC="https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA"

echo "Checking all 26 deployed contracts..."
echo "======================================="

# Arrays of contract names and addresses
declare -a names=(
"FROST" "SPV" "MultiPoolDAO"
"Factory" "Deployer" "TokenFactory"
"CalcRegistry" "FPPS" "PPLNS" "PPS" "SCORE"
"OracleReg" "Aggregator" "Validator"
"sBTC" "sDOGE" "sLTC"
"CoreImpl" "RewardsImpl" "RedemptionImpl" "ExtensionsImpl"
"RewardHandler" "RedemptionHandler"
)

declare -a addrs=(
"0x94F5cb5AEfBD21AD0Cd1BCfA0fF4bdE83D2461Ac"
"0x8a133E0f5Cb4a37581a28a97743dFAEdd5886391"
"0x7097C7d9763E594b10Bf295A51780BA806077D5C"
"0x3a79AeE7Da2E5a84ef0C5D2D1371539B33c6625c"
"0x1CDC107F22705c751f55a89dEdCc679338CE17Dc"
"0x65F6B601B631265BfdC6ba7568F4Cf1d83A39357"
"0x98DBb9BB4F411807690B9ef10C6238370D854439"
"0x255eE58729001C5B11a41901875FE79404e3d470"
"0x90D71C1A274628E4f265dFC697840653a06bF95F"
"0x5A913BaD807F3f092e508e8bDE039496F30919e8"
"0xeB1573AbeA89DC1135fC5E44E1f8512433f9d950"
"0x9991898EE234b37A8B07d60148eF7d2AbE622C5B"
"0xF555D3511809785a5b99F296cba0BCF3c21d5EBD"
"0xa3C4DA25AA48B03d8969E857af0724BEa716E6CF"
"0x7c370585B81bde38d4DD116f441f40Ef0A2e7a83"
"0x4636Ae44B92A7588f89e7AFF0b866eE438eE1a78"
"0x6B5ef8cE51214d8Cd9B11A6706750dE747619DD3"
"0x9AC9f4Be3383c23cc74EcA7C0ae279425f3A6675"
"0x284553273c32B7124e0A7Dab3F0807363A06Df1A"
"0x8BF90C57853e4bF3F02AEf9f0Bc578dFE7E7d9F1"
"0x60B5B5a7189FEbDDa70caB414Bf3239d136693cC"
"0xdc966354EFbc4f892D1161f2E172188e53696282"
"0xf35d7CDc6A89c4e89473568f3Bf0Af65d96A1828"
)

deployed=0
failed=0

for i in "${!names[@]}"; do
    name="${names[$i]}"
    addr="${addrs[$i]}"
    
    size=$(cast codesize "$addr" --rpc-url "$RPC" 2>/dev/null)
    
    if [ -z "$size" ] || [ "$size" = "0" ]; then
        echo "❌ $name: NOT DEPLOYED ($addr)"
        ((failed++))
    else
        echo "✅ $name: $size bytes ($addr)"
        ((deployed++))
    fi
done

echo "======================================="
echo "SUMMARY: $deployed deployed, $failed failed"

