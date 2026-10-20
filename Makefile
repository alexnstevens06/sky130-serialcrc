# tt_um_alexstevens_serialcrc - make lint test coverage synth
TOP      := tt_um_alexstevens_serialcrc
RTL      := rtl/sync2.v rtl/spi_slave.v rtl/uart_tx.v rtl/uart_rx.v \
            rtl/crc16_engine.v rtl/regfile.v rtl/$(TOP).v
TBS      := tb_crc16 tb_uart tb_top tb_dualedge
BUILD    := build
NICE     ?= nice -n 15
JOBS     ?= 4
IVERILOG ?= iverilog
VVP      ?= vvp
VERILATOR ?= verilator
VCOV     ?= verilator_coverage
YOSYS    ?= yosys
PYTHON   ?= python3

# sky130_fd_sc_hd typical-corner liberty, first match of:
#   $(SKY130_LIB) > $(PDK_ROOT)/sky130A/... > build/lib (make fetch-lib) > ~/eda/sky130
LIB_NAME  := sky130_fd_sc_hd__tt_025C_1v80.lib
PDK_LIB   := $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/$(LIB_NAME)
FETCH_LIB := $(BUILD)/lib/$(LIB_NAME)
HOME_LIB  := $(HOME)/eda/sky130/$(LIB_NAME)
LIB_URL   := https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD/master/test/sky130hd/$(LIB_NAME)
ifneq ($(SKY130_LIB),)
LIB ?= $(SKY130_LIB)
else ifneq ($(and $(PDK_ROOT),$(wildcard $(PDK_LIB))),)
LIB ?= $(PDK_LIB)
else ifneq ($(wildcard $(FETCH_LIB)),)
LIB ?= $(FETCH_LIB)
else
LIB ?= $(HOME_LIB)
endif

.PHONY: all lint test test-icarus test-cocotb coverage synth fetch-lib formal gls clean
all: lint test synth

SBY ?= sby
YOSYS_CONFIG ?= yosys-config
SIMCELLS ?= $(shell $(YOSYS_CONFIG) --datdir 2>/dev/null)/simcells.v
# tb_top elaborates CLK_HZ=10_000_000, BAUD=115200 (reset divisor 86).
GLS_CLK_HZ ?= 10000000
GLS_BAUD ?= 115200

test: test-icarus test-cocotb

lint:
	$(NICE) $(VERILATOR) --lint-only -Wall --top-module $(TOP) $(RTL)
	@echo "LINT PASS"

# ---- simulation (Icarus Verilog) ----
$(BUILD)/sim/%.vvp: tb/%.v $(RTL) | $(BUILD)/sim
	$(IVERILOG) -g2005 -Wall -Wno-timescale -o $@ -s $* $< $(RTL)

test-icarus: $(addprefix $(BUILD)/sim/,$(addsuffix .vvp,$(TBS)))
	@fail=0; for t in $(TBS); do \
	  $(NICE) $(VVP) -n $(BUILD)/sim/$$t.vvp > $(BUILD)/sim/$$t.log 2>&1; \
	  if grep -q '^PASS' $(BUILD)/sim/$$t.log; then \
	    echo "[PASS] $$t: $$(grep '^PASS' $(BUILD)/sim/$$t.log)"; \
	  else echo "[FAIL] $$t"; tail -n 30 $(BUILD)/sim/$$t.log; fail=1; fi; \
	done; exit $$fail

# Cocotb suites (Icarus). Needs: pip install -r tb/cocotb/requirements.txt
test-cocotb:
	$(PYTHON) tb/cocotb/run.py

# ---- coverage (Verilator line + toggle + branch) ----
coverage: | $(BUILD)/coverage
	@set -e; for t in $(TBS); do \
	  $(NICE) $(VERILATOR) --cc --exe --build --timing --coverage-line --coverage-toggle \
	    --timescale 1ns/1ps -Wno-fatal -Wno-lint -Wno-style -j $(JOBS) --prefix Vtop \
	    --top-module $$t -Mdir $(BUILD)/coverage/obj_$$t -o Vtop tb/$$t.v $(RTL) \
	    $(CURDIR)/tb/sim_main.cpp >$(BUILD)/coverage/$$t.build.log 2>&1 || \
	    { tail -n 30 $(BUILD)/coverage/$$t.build.log; exit 1; }; \
	  rm -rf $(BUILD)/coverage/run_$$t && mkdir -p $(BUILD)/coverage/run_$$t; \
	  (cd $(BUILD)/coverage/run_$$t && $(NICE) ../obj_$$t/Vtop > ../$$t.log 2>&1); \
	  mv $(BUILD)/coverage/run_$$t/coverage.dat $(BUILD)/coverage/$$t.dat; \
	  grep -q '^PASS' $(BUILD)/coverage/$$t.log || { echo "[FAIL] $$t (verilator)"; tail -n 30 $(BUILD)/coverage/$$t.log; exit 1; }; \
	  echo "[PASS] $$t (verilator)"; \
	done
	$(VCOV) --write $(BUILD)/coverage/merged.dat $(addprefix $(BUILD)/coverage/,$(addsuffix .dat,$(TBS)))
	$(VCOV) --write-info $(BUILD)/coverage/merged.info $(BUILD)/coverage/merged.dat
	$(VCOV) --annotate $(BUILD)/coverage/annotated --annotate-min 1 $(BUILD)/coverage/merged.dat > $(BUILD)/coverage/annotate.txt
	$(PYTHON) scripts/cov_summary.py $(BUILD)/coverage/merged.dat rtl/ | tee $(BUILD)/coverage/summary.txt

# ---- synthesis (Yosys -> sky130_fd_sc_hd) ----
synth: | $(BUILD)/synth
	@test -f "$(LIB)" || { echo "sky130 liberty not found: set SKY130_LIB=/path/to/$(LIB_NAME), set PDK_ROOT, or run make fetch-lib"; exit 1; }
	LIB=$(LIB) TOP=$(TOP) RTL="$(RTL)" OUT=$(BUILD)/synth $(NICE) $(YOSYS) -q -l $(BUILD)/synth/yosys.log -c synth/synth.tcl
	$(PYTHON) scripts/synth_summary.py $(BUILD)/synth/report.txt | tee $(BUILD)/synth/summary.txt

# ---- formal (SymbiYosys: CRC BMC, UART safety, register-file prove) ----
formal: | $(BUILD)/formal
	$(NICE) $(SBY) -f -d $(BUILD)/formal/crc16_bmc formal/crc16.sby bmc
	$(NICE) $(SBY) -f -d $(BUILD)/formal/crc16_cover formal/crc16.sby cover
	$(NICE) $(SBY) -f -d $(BUILD)/formal/uart_rx formal/uart_rx.sby
	$(NICE) $(SBY) -f -d $(BUILD)/formal/regfile formal/regfile.sby

# ---- generic-cell gate-level sim (no PDK, no place-and-route) ----
# Yosys `synth` to $_AND_ / $_DFF_* / ..., then Icarus + simcells.v on tb_top.
gls: | $(BUILD)/gls
	@test -f "$(SIMCELLS)" || { echo "simcells.v not found via yosys-config --datdir"; exit 1; }
	CLK_HZ=$(GLS_CLK_HZ) BAUD=$(GLS_BAUD) TOP=$(TOP) RTL="$(RTL)" OUT=$(BUILD)/gls \
	  $(NICE) $(YOSYS) -q -l $(BUILD)/gls/yosys.log -c synth/gls.tcl
	sed -e 's/tt_um_alexstevens_serialcrc #(.CLK_HZ(10_000_000), .BAUD(115_200)) dut/tt_um_alexstevens_serialcrc dut/' \
	  tb/tb_top.v > $(BUILD)/gls/tb_top.v
	$(IVERILOG) -g2005 -Wno-timescale -o $(BUILD)/gls/tb_top.vvp -s tb_top \
	  $(BUILD)/gls/tb_top.v $(BUILD)/gls/netlist.v $(SIMCELLS)
	$(NICE) $(VVP) -n $(BUILD)/gls/tb_top.vvp > $(BUILD)/gls/tb_top.log 2>&1
	@if grep -q '^PASS' $(BUILD)/gls/tb_top.log; then \
	  echo "[PASS] gls: $$(grep '^PASS' $(BUILD)/gls/tb_top.log)"; \
	else echo "[FAIL] gls"; tail -n 40 $(BUILD)/gls/tb_top.log; exit 1; fi

# Download only the typical-corner liberty file (no full PDK needed).
fetch-lib:
	mkdir -p $(BUILD)/lib
	curl -fsSL -o $(FETCH_LIB) $(LIB_URL)

$(BUILD)/sim $(BUILD)/coverage $(BUILD)/synth $(BUILD)/formal $(BUILD)/gls:
	mkdir -p $@

clean:
	rm -rf $(BUILD)
