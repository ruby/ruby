# Arm64

This module is responsible for encoding YJIT operands into an appropriate Arm64 encoding.

## Architecture

Every instruction in the Arm64 instruction set is 32 bits wide and is represented in little-endian order. Because they're all going to the same size, we represent each instruction by a struct that implements `From<T> for u32`, which contains the mechanism for encoding each instruction. The encoding for each instruction is shown in the documentation for the struct that ends up being created.

In general each set of bytes inside of the struct has either a direct value (usually a `u8`/`u16`) or some kind of `enum` that can be converted directly into a `u32`. For more complicated pieces of encoding (e.g., bitmask immediates) a corresponding module under the `arg` namespace is available.

## Helpful links

* [Arm A64 Instruction Set Architecture](https://developer.arm.com/documentation/ddi0596/2021-12?lang=en) Official documentation
* [armconverter.com](https://armconverter.com/) A website that encodes Arm assembly syntax
* [hatstone](https://github.com/tenderlove/hatstone) A wrapper around the Capstone disassembler written in Ruby
* [onlinedisassembler.com](https://onlinedisassembler.com/odaweb/) A web-based disassembler
