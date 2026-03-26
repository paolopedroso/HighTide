ifneq ($(wildcard $(DEV_FLAG)),)
export VERILOG_FILES = \
  $(wildcard $(BENCH_DESIGN_HOME)/src/odin/dev/repo/rtl/*.v)
else
export VERILOG_FILES = $(wildcard $(BENCH_DESIGN_HOME)/src/odin/*.v)
endif