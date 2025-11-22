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

RTL_FILES="$RTL_DIR/types/*.svh $COMP_DIR/*.sv $STAGES_DIR/*.sv"
# Include package files if needed
PKG_FILES="$RTL_DIR/*.sv"

# Verilate: compile SystemVerilog to C++
verilator -Wall \
          --cc $TB_DIR/${TOP_TB}.sv $RTL_FILES $PKG_FILES \
          -I$RTL_DIR \
          --exe $TB_DIR/${TOP_TB}.cpp \
          -Mdir $SIM_DIR \
          --timing \
          # --trace-fst --trace-max-array 1024 
          # Uncomment above line to enable tracing

# Build the simulation executable
make -C $SIM_DIR -f V${TOP_TB}.mk

# Run the simulation
$SIM_DIR/V${TOP_TB} +vcd=$WAVE_DIR/${TOP_TB}.vcd

# Open GTKWave for debugging (optional)
if [ "$1" == "--gtk" ]; then
    gtkwave $WAVE_DIR/${TOP_TB}.vcd &
fi