# tt_um_alexstevens_serialcrc - make lint test coverage synth
TOP      := tt_um_alexstevens_serialcrc
RTL      := rtl/sync2.v rtl/spi_slave.v rtl/uart_tx.v rtl/uart_rx.v \
            rtl/crc16_engine.v rtl/regfile.v rtl/$(TOP).v
TBS      := tb_crc16 tb_uart tb_top
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

.PHONY: all lint test coverage synth fetch-lib clean
all: lint test synth

lint:
	$(NICE) $(VERILATOR) --lint-only -Wall --top-module $(TOP) $(RTL)
	@echo "LINT PASS"

# ---- simulation (Icarus Verilog) ----
$(BUILD)/sim/%.vvp: tb/%.v $(RTL) | $(BUILD)/sim
	$(IVERILOG) -g2005 -Wall -Wno-timescale -o $@ -s $* $< $(RTL)

test: $(addprefix $(BUILD)/sim/,$(addsuffix .vvp,$(TBS)))
	@fail=0; for t in $(TBS); do \
	  $(NICE) $(VVP) -n $(BUILD)/sim/$$t.vvp > $(BUILD)/sim/$$t.log 2>&1; \
	  if grep -q '^PASS' $(BUILD)/sim/$$t.log; then \
	    echo "[PASS] $$t: $$(grep '^PASS' $(BUILD)/sim/$$t.log)"; \
	  else echo "[FAIL] $$t"; tail -n 30 $(BUILD)/sim/$$t.log; fail=1; fi; \
	done; exit $$fail

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

# Download only the typical-corner liberty file (no full PDK needed).
fetch-lib:
	mkdir -p $(BUILD)/lib
	curl -fsSL -o $(FETCH_LIB) $(LIB_URL)

$(BUILD)/sim $(BUILD)/coverage $(BUILD)/synth:
	mkdir -p $@

clean:
	rm -rf $(BUILD)
