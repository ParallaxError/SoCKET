CC = g++
SRC_DIR = src
BUILD_DIR = bin

CFLAGS = -std=c++17 -Wall -Wextra -O3 -march=native -mtune=native -I./${SRC_DIR}

SRCS = $(wildcard $(SRC_DIR)/*.cpp) $(wildcard $(SRC_DIR)/bitmap/*.cpp)
OBJS = $(patsubst %.cpp, $(BUILD_DIR)/%.o, $(notdir $(SRCS)))
TARGET = socket

all: build

build: ${OBJS}
	$(CC) $(CFLAGS) -o ${TARGET} $(OBJS)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/bitmap/%.cpp | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR):
	mkdir $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)/*.o
	rm -rf $(BUILD_DIR)
	rm -f $(TARGET)