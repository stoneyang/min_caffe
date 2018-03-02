PROJECT := caffe

CONFIG_FILE := Makefile.config
# Explicitly check for the config file, otherwise make -k will proceed anyway.
ifeq ($(wildcard $(CONFIG_FILE)),)
$(error $(CONFIG_FILE) not found. See $(CONFIG_FILE).example.)
endif
include $(CONFIG_FILE)

BUILD_DIR_LINK := $(BUILD_DIR)
ifeq ($(RELEASE_BUILD_DIR),)
	RELEASE_BUILD_DIR := .$(BUILD_DIR)_release
endif
ifeq ($(DEBUG_BUILD_DIR),)
	DEBUG_BUILD_DIR := .$(BUILD_DIR)_debug
endif

DEBUG ?= 0
ifeq ($(DEBUG), 1)
	BUILD_DIR := $(DEBUG_BUILD_DIR)
	OTHER_BUILD_DIR := $(RELEASE_BUILD_DIR)
else
	BUILD_DIR := $(RELEASE_BUILD_DIR)
	OTHER_BUILD_DIR := $(DEBUG_BUILD_DIR)
endif

# All of the directories containing code.
SRC_DIRS := $(shell find * -type d -exec bash -c "find {} -maxdepth 1 \
	\( -name '*.cpp' -o -name '*.proto' \) | grep -q ." \; -print)

# The target shared library name
LIBRARY_NAME := $(PROJECT)
LIB_BUILD_DIR := $(BUILD_DIR)/lib
STATIC_NAME := $(LIB_BUILD_DIR)/lib$(LIBRARY_NAME).a
DYNAMIC_VERSION_MAJOR 		:= 0
DYNAMIC_VERSION_MINOR 		:= 0
DYNAMIC_VERSION_REVISION 	:= 1
DYNAMIC_NAME_SHORT := lib$(LIBRARY_NAME).so
#DYNAMIC_SONAME_SHORT := $(DYNAMIC_NAME_SHORT).$(DYNAMIC_VERSION_MAJOR)
DYNAMIC_VERSIONED_NAME_SHORT := $(DYNAMIC_NAME_SHORT).$(DYNAMIC_VERSION_MAJOR).$(DYNAMIC_VERSION_MINOR).$(DYNAMIC_VERSION_REVISION)
DYNAMIC_NAME := $(LIB_BUILD_DIR)/$(DYNAMIC_VERSIONED_NAME_SHORT)
COMMON_FLAGS += -DCAFFE_VERSION=$(DYNAMIC_VERSION_MAJOR).$(DYNAMIC_VERSION_MINOR).$(DYNAMIC_VERSION_REVISION)

##############################
# Get all source files
##############################
# CXX_SRCS are the source files excluding the test ones.
CXX_SRCS := $(shell find src/$(PROJECT) ! -name "test_*.cpp" -name "*.cpp")
# CU_SRCS are the cuda source files
CU_SRCS := $(shell find src/$(PROJECT) ! -name "test_*.cu" -name "*.cu")
# TEST_SRCS are the test source files
# TOOL_SRCS are the source files for the tool binaries
TOOL_SRCS := $(shell find tools -name "*.cpp")
# EXAMPLE_SRCS are the source files for the example binaries
# BUILD_INCLUDE_DIR contains any generated header files we want to include.
BUILD_INCLUDE_DIR := $(BUILD_DIR)/src
# PROTO_SRCS are the protocol buffer definitions
PROTO_SRC_DIR := src/$(PROJECT)/proto
PROTO_SRCS := $(wildcard $(PROTO_SRC_DIR)/*.proto)
# PROTO_BUILD_DIR will contain the .cc and obj files generated from
# PROTO_SRCS; PROTO_BUILD_INCLUDE_DIR will contain the .h header files
PROTO_BUILD_DIR := $(BUILD_DIR)/$(PROTO_SRC_DIR)
PROTO_BUILD_INCLUDE_DIR := $(BUILD_INCLUDE_DIR)/$(PROJECT)/proto
# PY$(PROJECT)_SRC is the python wrapper for $(PROJECT)
PY$(PROJECT)_SRC := python/$(PROJECT)/_$(PROJECT).cpp
PY$(PROJECT)_SO := python/$(PROJECT)/_$(PROJECT).so
PY$(PROJECT)_HXX := include/$(PROJECT)/layers/python_layer.hpp

##############################
# Derive generated files
##############################
# The generated files for protocol buffers
PROTO_GEN_HEADER_SRCS := $(addprefix $(PROTO_BUILD_DIR)/, \
		$(notdir ${PROTO_SRCS:.proto=.pb.h}))
PROTO_GEN_HEADER := $(addprefix $(PROTO_BUILD_INCLUDE_DIR)/, \
		$(notdir ${PROTO_SRCS:.proto=.pb.h}))
PROTO_GEN_CC := $(addprefix $(BUILD_DIR)/, ${PROTO_SRCS:.proto=.pb.cc})
PY_PROTO_BUILD_DIR := python/$(PROJECT)/proto
PY_PROTO_INIT := python/$(PROJECT)/proto/__init__.py
PROTO_GEN_PY := $(foreach file,${PROTO_SRCS:.proto=_pb2.py}, \
		$(PY_PROTO_BUILD_DIR)/$(notdir $(file)))
# The objects corresponding to the source files
# These objects will be linked into the final shared library, so we
# exclude the tool, example, and test objects.
CXX_OBJS := $(addprefix $(BUILD_DIR)/, ${CXX_SRCS:.cpp=.o})
CU_OBJS := $(addprefix $(BUILD_DIR)/cuda/, ${CU_SRCS:.cu=.o})
PROTO_OBJS := ${PROTO_GEN_CC:.cc=.o}
OBJS := $(PROTO_OBJS) $(CXX_OBJS) $(CU_OBJS)
# tool, example, and test objects
TOOL_OBJS := $(addprefix $(BUILD_DIR)/, ${TOOL_SRCS:.cpp=.o})
TOOL_BUILD_DIR := $(BUILD_DIR)/tools
# Output files for automatic dependency generation
DEPS := ${CXX_OBJS:.o=.d} ${CU_OBJS:.o=.d}
# tool bins
TOOL_BINS := ${TOOL_OBJS:.o=.bin}
# symlinks to tool bins without the ".bin" extension
TOOL_BIN_LINKS := ${TOOL_BINS:.bin=}

##############################
# Derive compiler warning dump locations
##############################
WARNS_EXT := warnings.txt
CXX_WARNS := $(addprefix $(BUILD_DIR)/, ${CXX_SRCS:.cpp=.o.$(WARNS_EXT)})
CU_WARNS := $(addprefix $(BUILD_DIR)/cuda/, ${CU_SRCS:.cu=.o.$(WARNS_EXT)})
TOOL_WARNS := $(addprefix $(BUILD_DIR)/, ${TOOL_SRCS:.cpp=.o.$(WARNS_EXT)})
ALL_CXX_WARNS := $(CXX_WARNS) $(TOOL_WARNS)
ALL_CU_WARNS := $(CU_WARNS)
ALL_WARNS := $(ALL_CXX_WARNS) $(ALL_CU_WARNS)

EMPTY_WARN_REPORT := $(BUILD_DIR)/.$(WARNS_EXT)
NONEMPTY_WARN_REPORT := $(BUILD_DIR)/$(WARNS_EXT)

##############################
# Derive include and lib directories
##############################
CUDA_INCLUDE_DIR := $(CUDA_DIR)/include

CUDA_LIB_DIR :=
# add <cuda>/lib64 only if it exists
ifneq ("$(wildcard $(CUDA_DIR)/lib64)","")
	CUDA_LIB_DIR += $(CUDA_DIR)/lib64
endif
CUDA_LIB_DIR += $(CUDA_DIR)/lib

INCLUDE_DIRS += $(BUILD_INCLUDE_DIR) ./src ./include
ifneq ($(CPU_ONLY), 1)
	INCLUDE_DIRS += $(CUDA_INCLUDE_DIR)
	LIBRARY_DIRS += $(CUDA_LIB_DIR)
	LIBRARIES := cudart cublas curand
endif

LIBRARIES += glog gflags protobuf boost_system boost_filesystem m hdf5_hl hdf5

# handle IO dependencies
USE_LEVELDB ?= 1
USE_LMDB ?= 1
USE_OPENCV ?= 1

ifeq ($(USE_LEVELDB), 1)
	LIBRARIES += leveldb snappy
endif
ifeq ($(USE_LMDB), 1)
	LIBRARIES += lmdb
endif
ifeq ($(USE_OPENCV), 1)
	LIBRARIES += opencv_core opencv_highgui opencv_imgproc

	ifeq ($(OPENCV_VERSION), 3)
		LIBRARIES += opencv_imgcodecs
	endif

endif
PYTHON_LIBRARIES ?= boost_python python2.7
WARNINGS := -Wall -Wno-sign-compare

##############################
# Set build directories
##############################

ALL_BUILD_DIRS := $(sort $(BUILD_DIR) $(addprefix $(BUILD_DIR)/, $(SRC_DIRS)) \
	$(addprefix $(BUILD_DIR)/cuda/, $(SRC_DIRS)) \
	$(LIB_BUILD_DIR) $(PY_PROTO_BUILD_DIR) \
	$(PROTO_BUILD_INCLUDE_DIR))

##############################
# Configure build
##############################

# Determine platform
UNAME := $(shell uname -s)
ifeq ($(UNAME), Linux)
	LINUX := 1
else ifeq ($(UNAME), Darwin)
	OSX := 1
	OSX_MAJOR_VERSION := $(shell sw_vers -productVersion | cut -f 1 -d .)
	OSX_MINOR_VERSION := $(shell sw_vers -productVersion | cut -f 2 -d .)
endif

# Linux
ifeq ($(LINUX), 1)
	CXX ?= /usr/bin/g++
	GCCVERSION := $(shell $(CXX) -dumpversion | cut -f1,2 -d.)
	# older versions of gcc are too dumb to build boost with -Wuninitalized
	ifeq ($(shell echo | awk '{exit $(GCCVERSION) < 4.6;}'), 1)
		WARNINGS += -Wno-uninitialized
	endif
	# boost::thread is reasonably called boost_thread (compare OS X)
	# We will also explicitly add stdc++ to the link target.
	LIBRARIES += boost_thread stdc++
	VERSIONFLAGS += -Wl,-soname,$(DYNAMIC_VERSIONED_NAME_SHORT) -Wl,-rpath,$(ORIGIN)/../lib
endif

# OS X:
# clang++ instead of g++
# libstdc++ for NVCC compatibility on OS X >= 10.9 with CUDA < 7.0
ifeq ($(OSX), 1)
	CXX := /usr/bin/clang++
	ifneq ($(CPU_ONLY), 1)
		CUDA_VERSION := $(shell $(CUDA_DIR)/bin/nvcc -V | grep -o 'release [0-9.]*' | tr -d '[a-z ]')
		ifeq ($(shell echo | awk '{exit $(CUDA_VERSION) < 7.0;}'), 1)
			CXXFLAGS += -stdlib=libstdc++
			LINKFLAGS += -stdlib=libstdc++
		endif
		# clang throws this warning for cuda headers
		WARNINGS += -Wno-unneeded-internal-declaration
		# 10.11 strips DYLD_* env vars so link CUDA (rpath is available on 10.5+)
		OSX_10_OR_LATER   := $(shell [ $(OSX_MAJOR_VERSION) -ge 10 ] && echo true)
		OSX_10_5_OR_LATER := $(shell [ $(OSX_MINOR_VERSION) -ge 5 ] && echo true)
		ifeq ($(OSX_10_OR_LATER),true)
			ifeq ($(OSX_10_5_OR_LATER),true)
				LDFLAGS += -Wl,-rpath,$(CUDA_LIB_DIR)
			endif
		endif
	endif
	# gtest needs to use its own tuple to not conflict with clang
	COMMON_FLAGS += -DGTEST_USE_OWN_TR1_TUPLE=1
	# boost::thread is called boost_thread-mt to mark multithreading on OS X
	LIBRARIES += boost_thread-mt
	# we need to explicitly ask for the rpath to be obeyed
	ORIGIN := @loader_path
	VERSIONFLAGS += -Wl,-install_name,@rpath/$(DYNAMIC_VERSIONED_NAME_SHORT) -Wl,-rpath,$(ORIGIN)/../../build/lib
else
	ORIGIN := \$$ORIGIN
endif

# Custom compiler
ifdef CUSTOM_CXX
	CXX := $(CUSTOM_CXX)
endif

# Static linking
ifneq (,$(findstring clang++,$(CXX)))
	STATIC_LINK_COMMAND := -Wl,-force_load $(STATIC_NAME)
else ifneq (,$(findstring g++,$(CXX)))
	STATIC_LINK_COMMAND := -Wl,--whole-archive $(STATIC_NAME) -Wl,--no-whole-archive
else
  # The following line must not be indented with a tab, since we are not inside a target
  $(error Cannot static link with the $(CXX) compiler)
endif

# Debugging
ifeq ($(DEBUG), 1)
	COMMON_FLAGS += -DDEBUG -g -O0
	NVCCFLAGS += -G
else
	COMMON_FLAGS += -DNDEBUG -O2
endif

# cuDNN acceleration configuration.
ifeq ($(USE_CUDNN), 1)
	LIBRARIES += cudnn
	COMMON_FLAGS += -DUSE_CUDNN
endif

# NCCL acceleration configuration
ifeq ($(USE_NCCL), 1)
	LIBRARIES += nccl
	COMMON_FLAGS += -DUSE_NCCL
endif

# configure IO libraries
ifeq ($(USE_OPENCV), 1)
	COMMON_FLAGS += -DUSE_OPENCV
endif
ifeq ($(USE_LEVELDB), 1)
	COMMON_FLAGS += -DUSE_LEVELDB
endif
ifeq ($(USE_LMDB), 1)
	COMMON_FLAGS += -DUSE_LMDB
ifeq ($(ALLOW_LMDB_NOLOCK), 1)
	COMMON_FLAGS += -DALLOW_LMDB_NOLOCK
endif
endif

# CPU-only configuration
ifeq ($(CPU_ONLY), 1)
	OBJS := $(PROTO_OBJS) $(CXX_OBJS)
	ALL_WARNS := $(ALL_CXX_WARNS)
	COMMON_FLAGS += -DCPU_ONLY
endif

# Python layer support
ifeq ($(WITH_PYTHON_LAYER), 1)
	COMMON_FLAGS += -DWITH_PYTHON_LAYER
	LIBRARIES += $(PYTHON_LIBRARIES)
endif

# BLAS configuration (default = ATLAS)
BLAS ?= atlas
ifeq ($(BLAS), mkl)
	# MKL
	LIBRARIES += mkl_rt
	COMMON_FLAGS += -DUSE_MKL
	MKLROOT ?= /opt/intel/mkl
	BLAS_INCLUDE ?= $(MKLROOT)/include
	BLAS_LIB ?= $(MKLROOT)/lib $(MKLROOT)/lib/intel64
else ifeq ($(BLAS), open)
	# OpenBLAS
	LIBRARIES += openblas
else
	# ATLAS
	ifeq ($(LINUX), 1)
		ifeq ($(BLAS), atlas)
			# Linux simply has cblas and atlas
			LIBRARIES += cblas atlas
		endif
	else ifeq ($(OSX), 1)
		# OS X packages atlas as the vecLib framework
		LIBRARIES += cblas
		# 10.10 has accelerate while 10.9 has veclib
		XCODE_CLT_VER := $(shell pkgutil --pkg-info=com.apple.pkg.CLTools_Executables | grep 'version' | sed 's/[^0-9]*\([0-9]\).*/\1/')
		XCODE_CLT_GEQ_7 := $(shell [ $(XCODE_CLT_VER) -gt 6 ] && echo 1)
		XCODE_CLT_GEQ_6 := $(shell [ $(XCODE_CLT_VER) -gt 5 ] && echo 1)
		ifeq ($(XCODE_CLT_GEQ_7), 1)
			BLAS_INCLUDE ?= /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/$(shell ls /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/ | sort | tail -1)/System/Library/Frameworks/Accelerate.framework/Versions/A/Frameworks/vecLib.framework/Versions/A/Headers
		else ifeq ($(XCODE_CLT_GEQ_6), 1)
			BLAS_INCLUDE ?= /System/Library/Frameworks/Accelerate.framework/Versions/Current/Frameworks/vecLib.framework/Headers/
			LDFLAGS += -framework Accelerate
		else
			BLAS_INCLUDE ?= /System/Library/Frameworks/vecLib.framework/Versions/Current/Headers/
			LDFLAGS += -framework vecLib
		endif
	endif
endif
INCLUDE_DIRS += $(BLAS_INCLUDE)
LIBRARY_DIRS += $(BLAS_LIB)

LIBRARY_DIRS += $(LIB_BUILD_DIR)

# Automatic dependency generation (nvcc is handled separately)
CXXFLAGS += -MMD -MP

# Complete build flags.
COMMON_FLAGS += $(foreach includedir,$(INCLUDE_DIRS),-I$(includedir))
CXXFLAGS += -pthread -fPIC $(COMMON_FLAGS) $(WARNINGS)
NVCCFLAGS += -ccbin=$(CXX) -Xcompiler -fPIC $(COMMON_FLAGS)
LINKFLAGS += -pthread -fPIC $(COMMON_FLAGS) $(WARNINGS)

LDFLAGS += $(foreach librarydir,$(LIBRARY_DIRS),-L$(librarydir)) \
		$(foreach library,$(LIBRARIES),-l$(library))
PYTHON_LDFLAGS := $(LDFLAGS) $(foreach library,$(PYTHON_LIBRARIES),-l$(library))

##############################
# Define build targets
##############################
.PHONY: all lib clean tools proto py py$(PROJECT)

all: lib tools

lib: $(STATIC_NAME) $(DYNAMIC_NAME)

tools: $(TOOL_BINS) $(TOOL_BIN_LINKS)

py$(PROJECT): py

py: $(PY$(PROJECT)_SO) $(PROTO_GEN_PY)

$(PY$(PROJECT)_SO): $(PY$(PROJECT)_SRC) $(PY$(PROJECT)_HXX) | $(DYNAMIC_NAME)
	@ echo CXX/LD -o $@ $<
	$(Q)$(CXX) -shared -o $@ $(PY$(PROJECT)_SRC) \
		-o $@ $(LINKFLAGS) -l$(LIBRARY_NAME) $(PYTHON_LDFLAGS) \
		-Wl,-rpath,$(ORIGIN)/../../build/lib

$(BUILD_DIR_LINK): $(BUILD_DIR)/.linked

# Create a target ".linked" in this BUILD_DIR to tell Make that the "build" link
# is currently correct, then delete the one in the OTHER_BUILD_DIR in case it
# exists and $(DEBUG) is toggled later.
$(BUILD_DIR)/.linked:
	@ mkdir -p $(BUILD_DIR)
	@ $(RM) $(OTHER_BUILD_DIR)/.linked
	@ $(RM) -r $(BUILD_DIR_LINK)
	@ ln -s $(BUILD_DIR) $(BUILD_DIR_LINK)
	@ touch $@

$(ALL_BUILD_DIRS): | $(BUILD_DIR_LINK)
	@ mkdir -p $@

$(DYNAMIC_NAME): $(OBJS) | $(LIB_BUILD_DIR)
	@ echo LD -o $@
	$(Q)$(CXX) -shared -o $@ $(OBJS) $(VERSIONFLAGS) $(LINKFLAGS) $(LDFLAGS)
	@ cd $(BUILD_DIR)/lib; rm -f $(DYNAMIC_NAME_SHORT);   ln -s $(DYNAMIC_VERSIONED_NAME_SHORT) $(DYNAMIC_NAME_SHORT)

$(STATIC_NAME): $(OBJS) | $(LIB_BUILD_DIR)
	@ echo AR -o $@
	$(Q)ar rcs $@ $(OBJS)

$(BUILD_DIR)/%.o: %.cpp $(PROTO_GEN_HEADER) | $(ALL_BUILD_DIRS)
	@ echo CXX $<
	$(Q)$(CXX) $< $(CXXFLAGS) -c -o $@ 2> $@.$(WARNS_EXT) \
		|| (cat $@.$(WARNS_EXT); exit 1)
	@ cat $@.$(WARNS_EXT)

$(PROTO_BUILD_DIR)/%.pb.o: $(PROTO_BUILD_DIR)/%.pb.cc $(PROTO_GEN_HEADER) \
		| $(PROTO_BUILD_DIR)
	@ echo CXX $<
	$(Q)$(CXX) $< $(CXXFLAGS) -c -o $@ 2> $@.$(WARNS_EXT) \
		|| (cat $@.$(WARNS_EXT); exit 1)
	@ cat $@.$(WARNS_EXT)

$(BUILD_DIR)/cuda/%.o: %.cu | $(ALL_BUILD_DIRS)
	@ echo NVCC $<
	$(Q)$(CUDA_DIR)/bin/nvcc $(NVCCFLAGS) $(CUDA_ARCH) -M $< -o ${@:.o=.d} \
		-odir $(@D)
	$(Q)$(CUDA_DIR)/bin/nvcc $(NVCCFLAGS) $(CUDA_ARCH) -c $< -o $@ 2> $@.$(WARNS_EXT) \
		|| (cat $@.$(WARNS_EXT); exit 1)
	@ cat $@.$(WARNS_EXT)

# Target for extension-less symlinks to tool binaries with extension '*.bin'.
$(TOOL_BUILD_DIR)/%: $(TOOL_BUILD_DIR)/%.bin | $(TOOL_BUILD_DIR)
	@ $(RM) $@
	@ ln -s $(notdir $<) $@

$(TOOL_BINS): %.bin : %.o | $(DYNAMIC_NAME)
	@ echo CXX/LD -o $@
	$(Q)$(CXX) $< -o $@ $(LINKFLAGS) -l$(LIBRARY_NAME) $(LDFLAGS) \
		-Wl,-rpath,$(ORIGIN)/../lib

proto: $(PROTO_GEN_CC) $(PROTO_GEN_HEADER)

$(PROTO_BUILD_DIR)/%.pb.cc $(PROTO_BUILD_DIR)/%.pb.h : \
		$(PROTO_SRC_DIR)/%.proto | $(PROTO_BUILD_DIR)
	@ echo PROTOC $<
	$(Q)protoc --proto_path=$(PROTO_SRC_DIR) --cpp_out=$(PROTO_BUILD_DIR) $<

$(PY_PROTO_BUILD_DIR)/%_pb2.py : $(PROTO_SRC_DIR)/%.proto \
		$(PY_PROTO_INIT) | $(PY_PROTO_BUILD_DIR)
	@ echo PROTOC \(python\) $<
	$(Q)protoc --proto_path=$(PROTO_SRC_DIR) --python_out=$(PY_PROTO_BUILD_DIR) $<

$(PY_PROTO_INIT): | $(PY_PROTO_BUILD_DIR)
	touch $(PY_PROTO_INIT)

clean:
	@- $(RM) -rf $(ALL_BUILD_DIRS)
	@- $(RM) -rf $(OTHER_BUILD_DIR)
	@- $(RM) -rf $(BUILD_DIR_LINK)
	@- $(RM) $(PY$(PROJECT)_SO)

-include $(DEPS)
