export DESIGN_NAME	= ODIN
export PLATFORM		= sky130hd

-include $(BENCH_DESIGN_HOME)/src/$(DESIGN_NAME)/verilog.mk

export SDC_FILE			= $(BENCH_DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NAME)/constraint.sdc

export PLACE_DENSITY	= 0.6

export CORE_UTILIZATION	= 40

export SYNTH_MOCK_LARGE_MEMORIES = 1
