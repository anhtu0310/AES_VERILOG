# AES-128 cores: simulation, lint and synthesis.
#
#   make test     generate vectors and run tb/tb_aes.v (both cores)
#   make lint     Verilator -Wall on both cores
#   make synth    Yosys Xilinx 7-series synthesis, LUT/FF per core
#   make selftest check tools/aes_ref.py against FIPS-197 / SP 800-38A
#
#   make test NVEC=1000 SEED=7   more / different random vectors
#   make test VCD=1              dump build/tb_aes.vcd

RTL    := rtl/aes128_iter.v rtl/aes128_pipe.v
HDR    := rtl/aes_functions.vh rtl/aes_sbox.vh
BUILD  := build
PYTHON ?= python3
NVEC   ?= 200
SEED   ?= 1

.PHONY: test lint synth selftest clean

test: $(BUILD)/tb_aes.vvp $(BUILD)/vectors.txt
	vvp -n $< +VEC=$(BUILD)/vectors.txt +VEC2=tb/vectors_legacy.txt +SEED=$(SEED) $(if $(VCD),+VCD) \
	  | tee $(BUILD)/tb_aes.log
	@grep -q "^TEST PASSED" $(BUILD)/tb_aes.log

selftest:
	$(PYTHON) tools/aes_ref.py selftest

$(BUILD)/vectors.txt: tools/aes_ref.py FORCE | $(BUILD)
	$(PYTHON) tools/aes_ref.py vectors -n $(NVEC) --seed $(SEED) -o $@

$(BUILD)/tb_aes.vvp: $(RTL) $(HDR) tb/tb_aes.v | $(BUILD)
	iverilog -g2012 -Wall -Irtl -o $@ -s tb_aes tb/tb_aes.v $(RTL)

# rtl/aes_sbox.vh is generated; regenerate with: make sbox
sbox:
	$(PYTHON) tools/aes_ref.py sbox-vh -o rtl/aes_sbox.vh

lint:
	verilator --lint-only -Wall -Irtl --top-module aes128_iter $(RTL)
	verilator --lint-only -Wall -Irtl --top-module aes128_pipe $(RTL)

synth: | $(BUILD)
	@for top in aes128_iter aes128_pipe; do \
	  yosys -q -p "read_verilog -Irtl $(RTL); synth_xilinx -top $$top -family xc7 -flatten; tee -o $(BUILD)/synth_$$top.txt stat" > /dev/null; \
	  printf "%-12s" $$top; \
	  awk '/LUT[1-6] /{l+=$$2} /FDRE|FDCE|FDSE|FDPE/{f+=$$2} /MUXF7/{m7+=$$2} /MUXF8/{m8+=$$2} END{printf " LUT %6d  FF %6d  MUXF7 %5d  MUXF8 %5d\n", l, f, m7, m8}' $(BUILD)/synth_$$top.txt; \
	done

$(BUILD):
	mkdir -p $@

FORCE:

clean:
	rm -rf $(BUILD)
