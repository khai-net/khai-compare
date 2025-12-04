CC = gcc
THIRD_PARTY = ./third-party
CFLAGS = -Wall -Wextra -g -IHeaders -I$(THIRD_PARTY)/include
LDFLAGS = -L$(THIRD_PARTY)/lib -lbson2 -lzstd

TARGET = khai-compare
SRC = Source/analysis_input_parser.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC) $(LDFLAGS)

test: $(TARGET)
	./$(TARGET) sample_input.json output.json
	@echo "\n--- Output file contents ---"
	@cat output.json

clean:
	rm -f $(TARGET) output.json

.PHONY: all test clean
