CC       ?= cc
CFLAGS   ?= -O2 -std=c11 -D_GNU_SOURCE
WARN     := -Wall -Wextra -Wno-unused-parameter
LDFLAGS  ?=
LDLIBS   := -lpthread -lm
VERSION  := 0.3.0

SRC := $(wildcard src/*.c src/*/*.c src/*/*/*.c)
OBJ := $(SRC:.c=.o)
BIN := tachyon

CFLAGS += -Isrc -DTACHYON_VERSION='"$(VERSION)"'

# The workspace filesystem is mounted noexec, so builds land in /tmp by default.
# Override with `make OUT=/your/path`.
OUT ?= /tmp/tbuild

.PHONY: all clean test bench install

all: $(BIN)

$(BIN): $(OBJ)
	$(CC) $(CFLAGS) -o $(BIN) $(OBJ) $(LDFLAGS) $(LDLIBS)

%.o: %.c
	$(CC) $(CFLAGS) $(WARN) -c -o $@ $<

# Builds and runs from an executable location.
run: $(OBJ)
	@mkdir -p $(OUT)
	$(CC) $(CFLAGS) -o $(OUT)/$(BIN) $(OBJ) $(LDFLAGS) $(LDLIBS)
	@echo "built $(OUT)/$(BIN)"

clean:
	rm -f $(OBJ) $(BIN)

test: run
	./bench/run_tests.sh

bench: run
	python3 bench/bench.py
