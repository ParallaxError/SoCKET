#!/bin/bash

# Project directories
RTL_DIR=rtl
COMP_DIR=$RTL_DIR/components
STAGES_DIR=$RTL_DIR/stages
TB_DIR=tb
WAVE_DIR=wave
SIM_DIR=sim_build

mkdir -p $SIM_DIR
mkdir -p $WAVE_DIR

# Top-level testbench
TOP_TB=top_tb
HARNESS_FILES="$TB_DIR/bitmap/bitmap.cpp"

RTL_FILES="$RTL_DIR/types/*.svh $COMP_DIR/*.sv $STAGES_DIR/*.sv"
# Include package files if needed
PKG_FILES="$RTL_DIR/*.sv"

# Warnings to ignore
IGNORED=(
    -Wno-WIDTHEXPAND
    -Wno-WIDTHTRUNC
    -Wno-PINCONNECTEMPTY
    -Wno-UNUSEDSIGNAL # Should turn this on later for a check
)

IGNORED_JOINED=$(IFS=" " ; echo "${IGNORED[*]}")

# Verilate: compile SystemVerilog to C++
if [ "$1" == "--trace" ]; then
    TRACE_FLAGS="--trace-fst --trace-max-array 1024"
else
    TRACE_FLAGS=""
fi

verilator -Wall \
      --cc $TB_DIR/${TOP_TB}.sv $RTL_FILES $PKG_FILES \
      -I$RTL_DIR \
      --exe $TB_DIR/${TOP_TB}.cpp $HARNESS_FILES \
      -Mdir $SIM_DIR \
      --timing \
      $TRACE_FLAGS \
      $IGNORED_JOINED

# Build the simulation executable
make -C $SIM_DIR -f V${TOP_TB}.mk

# Run the simulation
$SIM_DIR/V${TOP_TB} +vcd=$WAVE_DIR/${TOP_TB}.vcd