# CMAKE generated file: DO NOT EDIT!
# Generated by "Unix Makefiles" Generator, CMake Version 3.22

# Delete rule output on recipe failure.
.DELETE_ON_ERROR:

#=============================================================================
# Special targets provided by cmake.

# Disable implicit rules so canonical targets will work.
.SUFFIXES:

# Disable VCS-based implicit rules.
% : %,v

# Disable VCS-based implicit rules.
% : RCS/%

# Disable VCS-based implicit rules.
% : RCS/%,v

# Disable VCS-based implicit rules.
% : SCCS/s.%

# Disable VCS-based implicit rules.
% : s.%

.SUFFIXES: .hpux_make_needs_suffix_list

# Command-line flag to silence nested $(MAKE).
$(VERBOSE)MAKESILENT = -s

#Suppress display of executed commands.
$(VERBOSE).SILENT:

# A target that is always out of date.
cmake_force:
.PHONY : cmake_force

#=============================================================================
# Set environment variables for the build.

# The shell in which to execute make rules.
SHELL = /bin/sh

# The CMake executable.
CMAKE_COMMAND = /opt/homebrew/Cellar/cmake/3.22.1/bin/cmake

# The command to remove a file.
RM = /opt/homebrew/Cellar/cmake/3.22.1/bin/cmake -E rm -f

# Escaping for special characters.
EQUALS = =

# The top-level source directory on which CMake was run.
CMAKE_SOURCE_DIR = /Users/mikerenoir/projects/Telegram-macOS/Telegram/submodules/telegram-ios/third-party/mozjpeg/mozjpeg

# The top-level build directory on which CMake was run.
CMAKE_BINARY_DIR = /Users/mikerenoir/projects/Telegram-macOS/Telegram/core-xprojects/Mozjpeg/build/x86_64

# Utility rule file for jsimdcfg.

# Include any custom commands dependencies for this target.
include simd/CMakeFiles/jsimdcfg.dir/compiler_depend.make

# Include the progress variables for this target.
include simd/CMakeFiles/jsimdcfg.dir/progress.make

simd/CMakeFiles/jsimdcfg:
	cd /Users/mikerenoir/projects/Telegram-macOS/Telegram/core-xprojects/Mozjpeg/build/x86_64/simd && /Applications/Xcode_14_0_1.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -E -I/Users/mikerenoir/projects/Telegram-macOS/Telegram/core-xprojects/Mozjpeg/build/x86_64 -I/Users/mikerenoir/projects/Telegram-macOS/Telegram/core-xprojects/Mozjpeg/build/x86_64/simd -I/Users/mikerenoir/projects/Telegram-macOS/Telegram/submodules/telegram-ios/third-party/mozjpeg/mozjpeg/simd /Users/mikerenoir/projects/Telegram-macOS/Telegram/submodules/telegram-ios/third-party/mozjpeg/mozjpeg/simd/nasm/jsimdcfg.inc.h | grep -E '^[;%]|^\ %' | sed 's%_cpp_protection_%%' | sed 's@% define@%define@g' >/Users/mikerenoir/projects/Telegram-macOS/Telegram/submodules/telegram-ios/third-party/mozjpeg/mozjpeg/simd/nasm/jsimdcfg.inc

jsimdcfg: simd/CMakeFiles/jsimdcfg
jsimdcfg: simd/CMakeFiles/jsimdcfg.dir/build.make
.PHONY : jsimdcfg

# Rule to build all files generated by this target.
simd/CMakeFiles/jsimdcfg.dir/build: jsimdcfg
.PHONY : simd/CMakeFiles/jsimdcfg.dir/build

simd/CMakeFiles/jsimdcfg.dir/clean:
	cd /Users/mikerenoir/projects/Telegram-macOS/Telegram/core-xprojects/Mozjpeg/build/x86_64/simd && $(CMAKE_COMMAND) -P CMakeFiles/jsimdcfg.dir/cmake_clean.cmake
.PHONY : simd/CMakeFiles/jsimdcfg.dir/clean

simd/CMakeFiles/jsimdcfg.dir/depend:
	cd /Users/mikerenoir/projects/Telegram-macOS/Telegram/core-xprojects/Mozjpeg/build/x86_64 && $(CMAKE_COMMAND) -E cmake_depends "Unix Makefiles" /Users/mikerenoir/projects/Telegram-macOS/Telegram/submodules/telegram-ios/third-party/mozjpeg/mozjpeg /Users/mikerenoir/projects/Telegram-macOS/Telegram/submodules/telegram-ios/third-party/mozjpeg/mozjpeg/simd /Users/mikerenoir/projects/Telegram-macOS/Telegram/core-xprojects/Mozjpeg/build/x86_64 /Users/mikerenoir/projects/Telegram-macOS/Telegram/core-xprojects/Mozjpeg/build/x86_64/simd /Users/mikerenoir/projects/Telegram-macOS/Telegram/core-xprojects/Mozjpeg/build/x86_64/simd/CMakeFiles/jsimdcfg.dir/DependInfo.cmake --color=$(COLOR)
.PHONY : simd/CMakeFiles/jsimdcfg.dir/depend

