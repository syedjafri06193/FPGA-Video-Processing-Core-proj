# Simulation and verification flow.
#
#   make            generate vectors and run every testbench
#   make vectors    regenerate the golden vectors and LUT banks
#   make sim        unit testbenches only
#   make regress    full-frame comparison against the Python model
#   make wave TB=tb_sobel    rerun one testbench with a VCD dump
#   make lint       synthesis-oriented lint (needs verilator)
#   make clean
#
# Every target is meant to run in seconds.  An iteration in simulation is the
# whole point: the board is for confirming that something which already works
# in simulation also works in silicon, not for finding logic bugs
# (design.md section 12.4).

IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3
IFLAGS   := -g2012 -I rtl -Wall -Wno-timescale

BUILD := build
RTL   := $(wildcard rtl/*.v)
PRIMS := sim/models/xilinx_prims.v

W := 64
H := 64
THRESHOLD := 64
GRADES := identity warm cool teal_orange high_contrast mono bleach_bypass
MODES  := 0 1 2 3
REGRESS_GRADES := identity teal_orange

MODE_0_NAME := pass
MODE_1_NAME := lut
MODE_2_NAME := edges
MODE_3_NAME := overlay

.PHONY: all vectors sim regress clean lint wave help

all: vectors sim regress
	@echo
	@echo "================================================================"
	@echo " all testbenches passed, and the pipeline matches the golden"
	@echo " model pixel for pixel in every mode"
	@echo "================================================================"

help:
	@sed -n '2,15p' Makefile | sed 's/^# \{0,1\}//'

# ---------------------------------------------------------------- vectors

vectors: sim/vectors/input.hex

sim/vectors/input.hex: model/gen_vectors.py model/golden.py model/make_lut.py
	@mkdir -p $(BUILD)
	$(PYTHON) model/gen_vectors.py --width $(W) --height $(H) --threshold $(THRESHOLD)

# ------------------------------------------------------------ unit tests

sim: $(BUILD)/tb_delay_line.log $(BUILD)/tb_video_timing.log \
     $(BUILD)/tb_tmds_encoder.log $(BUILD)/tb_dvi_tx.log \
     $(BUILD)/tb_line_buffer.log $(BUILD)/tb_sobel.log \
     $(BUILD)/tb_uart_rx.log $(BUILD)/tb_lut3d.log \
     $(BUILD)/tb_top_smoke.log
	@grep -h -E "^(PASS|FAIL)" $^ || true

$(BUILD)/tb_delay_line.log: sim/tb_delay_line.v rtl/delay_line.v | $(BUILD)
	$(IVERILOG) $(IFLAGS) -o $(BUILD)/tb_delay_line.vvp $^
	$(VVP) $(BUILD)/tb_delay_line.vvp | tee $@
	@! grep -q FAIL $@

$(BUILD)/tb_video_timing.log: sim/tb_video_timing.v rtl/video_timing.v | $(BUILD)
	$(IVERILOG) $(IFLAGS) -o $(BUILD)/tb_video_timing.vvp $^
	$(VVP) $(BUILD)/tb_video_timing.vvp | tee $@
	@! grep -q FAIL $@

$(BUILD)/tb_tmds_encoder.log: sim/tb_tmds_encoder.v rtl/tmds_encoder.v | $(BUILD)
	$(IVERILOG) $(IFLAGS) -o $(BUILD)/tb_tmds_encoder.vvp $^
	$(VVP) $(BUILD)/tb_tmds_encoder.vvp | tee $@
	@! grep -q FAIL $@

$(BUILD)/tb_dvi_tx.log: sim/tb_dvi_tx.v rtl/dvi_tx.v rtl/tmds_encoder.v \
                        rtl/serializer_10to1.v $(PRIMS) | $(BUILD)
	$(IVERILOG) $(IFLAGS) -o $(BUILD)/tb_dvi_tx.vvp $^
	$(VVP) $(BUILD)/tb_dvi_tx.vvp | tee $@
	@! grep -q FAIL $@

$(BUILD)/tb_line_buffer.log: sim/tb_line_buffer.v rtl/line_buffer.v | $(BUILD)
	$(IVERILOG) $(IFLAGS) -o $(BUILD)/tb_line_buffer.vvp $^
	$(VVP) $(BUILD)/tb_line_buffer.vvp | tee $@
	@! grep -q FAIL $@

$(BUILD)/tb_sobel.log: sim/tb_sobel.v rtl/sobel.v | $(BUILD)
	$(IVERILOG) $(IFLAGS) -o $(BUILD)/tb_sobel.vvp $^
	$(VVP) $(BUILD)/tb_sobel.vvp | tee $@
	@! grep -q FAIL $@

$(BUILD)/tb_uart_rx.log: sim/tb_uart_rx.v rtl/uart_rx.v | $(BUILD)
	$(IVERILOG) $(IFLAGS) -o $(BUILD)/tb_uart_rx.vvp $^
	$(VVP) $(BUILD)/tb_uart_rx.vvp | tee $@
	@! grep -q FAIL $@

# Every grade, because a LUT bug can hide in one grade's data.
$(BUILD)/tb_lut3d.log: sim/tb_lut3d.v rtl/lut3d.v rtl/lut_bank.v rtl/lerp8.v \
                       rtl/delay_line.v sim/vectors/input.hex | $(BUILD)
	$(IVERILOG) $(IFLAGS) -o $(BUILD)/tb_lut3d.vvp sim/tb_lut3d.v rtl/lut3d.v \
	    rtl/lut_bank.v rtl/lerp8.v rtl/delay_line.v
	@rm -f $@
	@for g in $(GRADES); do \
	    $(VVP) $(BUILD)/tb_lut3d.vvp +grade=$$g | tee -a $@; \
	done
	@! grep -q FAIL $@

$(BUILD)/tb_top_smoke.log: sim/tb_top_smoke.v $(RTL) $(PRIMS) sim/vectors/input.hex | $(BUILD)
	$(IVERILOG) $(IFLAGS) -o $(BUILD)/tb_top_smoke.vvp sim/tb_top_smoke.v $(RTL) $(PRIMS)
	$(VVP) $(BUILD)/tb_top_smoke.vvp | tee $@
	@! grep -q FAIL $@

# ------------------------------------------------- full-frame regression

$(BUILD)/tb_pipeline.vvp: sim/tb_pipeline.v rtl/video_pipeline.v rtl/lut3d.v \
                          rtl/lut_bank.v rtl/lerp8.v rtl/delay_line.v \
                          rtl/line_buffer.v rtl/window_3x3.v rtl/rgb2luma.v \
                          rtl/sobel.v rtl/blend.v | $(BUILD)
	$(IVERILOG) $(IFLAGS) -o $@ $^

regress: $(BUILD)/tb_pipeline.vvp sim/vectors/input.hex
	@echo "--- full-frame comparison against model/golden.py ---"
	@fail=0; \
	for g in $(REGRESS_GRADES); do \
	  for m in $(MODES); do \
	    $(VVP) $(BUILD)/tb_pipeline.vvp +mode=$$m +grade=$$g +threshold=$(THRESHOLD) \
	        > $(BUILD)/pipeline_$${m}_$${g}.log 2>&1 || fail=1; \
	    case $$m in \
	      0) name=$(MODE_0_NAME);; 1) name=$(MODE_1_NAME);; \
	      2) name=$(MODE_2_NAME);; 3) name=$(MODE_3_NAME);; \
	    esac; \
	    $(PYTHON) model/compare.py $(BUILD)/output_mode$${m}_$${g}.hex \
	        sim/vectors/expected_$${name}_$${g}.hex \
	        --width $(W) --height $(H) --label "mode=$${name} grade=$${g}" || fail=1; \
	  done; \
	done; \
	exit $$fail

# ------------------------------------------------------------- utilities

wave:
	@test -n "$(TB)" || (echo "usage: make wave TB=tb_sobel" && false)
	$(VVP) $(BUILD)/$(TB).vvp +vcd
	@echo "wrote $(BUILD)/$(TB).vcd -- open with: gtkwave $(BUILD)/$(TB).vcd"

lint:
	verilator --lint-only -Wall -Irtl --top-module top $(RTL) $(PRIMS) 2>&1 | head -40

$(BUILD):
	@mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)

distclean: clean
	rm -rf sim/vectors
