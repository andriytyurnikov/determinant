# Makefile for building RISC-V compliance test binaries.
#
# Prerequisites:
#   - RISC-V cross-compiler (riscv64-unknown-elf-gcc or riscv32-unknown-elf-gcc)
#   - riscv-tests submodule initialized:
#       git submodule update --init --recursive
#
# Usage:
#   make            # build all test binaries
#   make rv32ui     # build only RV32I tests
#   make clean      # remove build artifacts
#
# Output: flat binary files in ../../src/compliance/bin/<extension>/<test>.bin

# Cross-compiler — prefer riscv64 (can target rv32 with -march/-mabi flags)
CC := $(shell which riscv32-unknown-elf-gcc 2>/dev/null || which riscv64-unknown-elf-gcc 2>/dev/null)
OBJCOPY := $(shell which riscv32-unknown-elf-objcopy 2>/dev/null || which riscv64-unknown-elf-objcopy 2>/dev/null)

ifeq ($(CC),)
$(error No RISC-V cross-compiler found. Install riscv-gnu-toolchain.)
endif

# Directories
RISCV_TESTS := riscv-tests-src
ISA_DIR := $(RISCV_TESTS)/isa
ENV_DIR := env/determinant
UPSTREAM_ENV := $(RISCV_TESTS)/env
BIN_DIR := ../../src/compliance/bin
BUILD_DIR := build

# Common compiler flags (GCC 12+ needs _zifencei before it accepts fence.i)
CFLAGS := -march=rv32i_m_a_zicsr_zifencei_zba_zbb_zbs -mabi=ilp32 -nostdlib -nostartfiles \
          -I$(ENV_DIR) -I$(UPSTREAM_ENV) -I$(ISA_DIR)/macros/scalar \
          -T$(ENV_DIR)/link.ld -DDETERMINANT

# Per-extension test lists (rv32ui skips ma_data; see README.md)
RV32UI_TESTS := add addi and andi auipc beq bge bgeu blt bltu bne fence_i \
                jal jalr lb lbu lh lhu lui lw or ori sb sh simple \
                sll slli slt slti sltiu sltu sra srai srl srli sub sw xor xori

# Include ld_st and st_ld tests (these are load-store pipeline tests)
RV32UI_TESTS += ld_st st_ld

RV32UM_TESTS := div divu mul mulh mulhsu mulhu rem remu
RV32UA_TESTS := amoadd_w amoand_w amomax_w amomaxu_w amomin_w amominu_w \
                amoor_w amoswap_w amoxor_w lrsc
RV32UC_TESTS := rvc
RV32UZBA_TESTS := sh1add sh2add sh3add
RV32UZBB_TESTS := andn clz cpop ctz max maxu min minu orc_b orn rev8 \
                  rol ror rori sext_b sext_h xnor zext_h
RV32UZBS_TESTS := bclr bclri bext bexti binv binvi bset bseti

# Generate binary paths
RV32UI_BINS := $(addprefix $(BIN_DIR)/rv32ui/,$(addsuffix .bin,$(RV32UI_TESTS)))
RV32UM_BINS := $(addprefix $(BIN_DIR)/rv32um/,$(addsuffix .bin,$(RV32UM_TESTS)))
RV32UA_BINS := $(addprefix $(BIN_DIR)/rv32ua/,$(addsuffix .bin,$(RV32UA_TESTS)))
RV32UC_BINS := $(addprefix $(BIN_DIR)/rv32uc/,$(addsuffix .bin,$(RV32UC_TESTS)))
RV32UZBA_BINS := $(addprefix $(BIN_DIR)/rv32uzba/,$(addsuffix .bin,$(RV32UZBA_TESTS)))
RV32UZBB_BINS := $(addprefix $(BIN_DIR)/rv32uzbb/,$(addsuffix .bin,$(RV32UZBB_TESTS)))
RV32UZBS_BINS := $(addprefix $(BIN_DIR)/rv32uzbs/,$(addsuffix .bin,$(RV32UZBS_TESTS)))

ALL_BINS := $(RV32UI_BINS) $(RV32UM_BINS) $(RV32UA_BINS) $(RV32UC_BINS) \
            $(RV32UZBA_BINS) $(RV32UZBB_BINS) $(RV32UZBS_BINS)

# Phony targets
.PHONY: all clean rv32ui rv32um rv32ua rv32uc rv32uzba rv32uzbb rv32uzbs

all: $(ALL_BINS)

rv32ui: $(RV32UI_BINS)
rv32um: $(RV32UM_BINS)
rv32ua: $(RV32UA_BINS)
rv32uc: $(RV32UC_BINS)
rv32uzba: $(RV32UZBA_BINS)
rv32uzbb: $(RV32UZBB_BINS)
rv32uzbs: $(RV32UZBS_BINS)

# RV32C needs compressed extension in -march
$(BIN_DIR)/rv32uc/%.bin: CFLAGS := -march=rv32i_m_a_c_zicsr -mabi=ilp32 -nostdlib -nostartfiles \
          -I$(ENV_DIR) -I$(UPSTREAM_ENV) -I$(ISA_DIR)/macros/scalar \
          -T$(ENV_DIR)/link.ld -DDETERMINANT

# Generic rule: .S → ELF → flat binary. The bin/ layout mirrors isa/
# (e.g. isa/rv32ui/add.S → bin/rv32ui/add.bin); the rv32* sources include
# their rv64* counterparts.
$(BIN_DIR)/%.bin: $(ISA_DIR)/%.S $(ENV_DIR)/riscv_test.h $(ENV_DIR)/link.ld
	@mkdir -p $(dir $@) $(dir $(BUILD_DIR)/$*)
	$(CC) $(CFLAGS) -o $(BUILD_DIR)/$*.elf $<
	$(OBJCOPY) -O binary $(BUILD_DIR)/$*.elf $@

# Removes the ELF intermediates only. The binaries in $(BIN_DIR) are checked in;
# use `make -B` to rebuild them all.
clean:
	rm -rf $(BUILD_DIR)

# Print discovered tests (useful for debugging)
.PHONY: list
list:
	@echo "RV32UI: $(RV32UI_TESTS)"
	@echo "RV32UM: $(RV32UM_TESTS)"
	@echo "RV32UA: $(RV32UA_TESTS)"
	@echo "RV32UC: $(RV32UC_TESTS)"
	@echo "RV32UZBA: $(RV32UZBA_TESTS)"
	@echo "RV32UZBB: $(RV32UZBB_TESTS)"
	@echo "RV32UZBS: $(RV32UZBS_TESTS)"
	@echo "Total: $(words $(ALL_BINS)) binaries"
