#!/bin/bash

RULES=(
    +parameter-name-style=localparam_style:ALL_CAPS
    +always-ff-non-blocking=waive_for_locals:true
)

RULES_JOINED=$(IFS=, ; echo "${RULES[*]}")

if [ "$1" == "--fix" ]; then
    FIX=true
else
    FIX=false
fi

if [ "$FIX" == true ]; then
    verible-verilog-format --inplace \
        $(find rtl -name "*.sv" -o -name "*.svh")
    verible-verilog-lint --rules=${RULES_JOINED} --autofix inplace \
    $(find rtl -name "*.sv" -o -name "*.svh")
else
    verible-verilog-lint --rules=${RULES_JOINED} \
        $(find rtl -name "*.sv" -o -name "*.svh")
fi