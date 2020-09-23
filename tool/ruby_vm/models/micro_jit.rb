#! /your/favourite/path/to/ruby
# -*- Ruby -*-
# -*- frozen_string_literal: true; -*-
# -*- warn_indent: true; -*-
#
# Copyright (c) 2020 Wu, Alan.  All rights reserved.
#
# This file is  a part of the programming language  Ruby.  Permission is hereby
# granted, to  either redistribute and/or  modify this file, provided  that the
# conditions  mentioned in  the file  COPYING are  met.  Consult  the file  for
# details.

module RubyVM::MicroJIT
  class << self
    def get_fileoff
      # use the load command to figure out the offset to the start of the content of vm.o
      `otool -l vm.o`.each_line do |line|
        if (fileoff = line[/fileoff (\d+)/, 1])
          p [__method__, line] if $DEBUG
          return fileoff.to_i
        end
      end
      raise
    end

    def get_symbol_offset(symbol)
      `nm vm.o`.each_line do |line|
        if (offset = line[Regexp.compile('(\h+).+' + Regexp.escape(symbol) + '\Z'), 1])
          p [__method__, line] if $DEBUG
          return Integer(offset, 16)
        end
      end
      raise
    end

    def readint8b(offset)
      bytes = IO.binread('vm.o', 8, offset)
      bytes.unpack('q').first #  this is native endian but we want little endian. it's fine if the host moachine is x86
    end

    def disassemble(offset)
      command = "objdump --x86-asm-syntax=intel --start-address=#{offset} --stop-address=#{offset+50} -d vm.o"
      puts "Running: #{command}"
      puts "feel free to verify with --reloc"
      disassembly = `#{command}`
      instructions = []
      puts disassembly if $DEBUG
      disassembly.each_line do |line|
        line = line.strip
        match_data = /\h+: ((?:\h\h\s?)+)\s+(\w+)/.match(line)
        if match_data
          bytes = match_data[1]
          mnemonic = match_data[2]
          instructions << [bytes, mnemonic, line]
          break if mnemonic == 'jmp'
        elsif !instructions.empty?
          p line
          raise "expected a continuous sequence of disassembly lines"
        end
      end

      jmp_idx = instructions.find_index { |_, mnemonic, _| mnemonic == 'jmp' }
      raise 'failed to find jmp' unless jmp_idx
      raise 'generated code for example too long' unless jmp_idx < 10
      handler_instructions = instructions[(0..jmp_idx)]

      puts "Disassembly for the example handler:"
      puts handler_instructions.map {|_, _, line| line}


      raise 'rip reference in example makes copying unsafe' if handler_instructions.any? { |_, _, full_line| full_line.downcase.include?('rip') }
      acceptable_mnemonics = %w(mov jmp lea call)
      unrecognized = nil
      handler_instructions.each { |i| unrecognized = i unless acceptable_mnemonics.include?(i[1]) }
      raise "found an unrecognized \"#{unrecognized[1]}\" instruction in the example. List of recognized instructions: #{acceptable_mnemonics.join(', ')}" if unrecognized
      raise 'found multiple jmp instructions' if handler_instructions.count { |_, mnemonic, _| mnemonic == 'jmp' } > 1
      raise "the jmp instruction seems to be relative which isn't copiable" if instructions[jmp_idx][0].split.size > 4
      raise 'found multiple call instructions' if handler_instructions.count { |_, mnemonic, _| mnemonic == 'call' } > 1
      call_idx = handler_instructions.find_index { |_, mnemonic, _| mnemonic == 'call' }


      @pre_call_bytes = []
      @post_call_bytes = []

      handler_instructions.take(call_idx).each do |bytes, mnemonic, _|
        @pre_call_bytes += bytes.split
      end

      handler_instructions[call_idx + 1, handler_instructions.size].each do |bytes, _, _|
        @post_call_bytes += bytes.split
      end
    end

    def scrape
      instruction_id = RubyVM::Instructions.find_index { |insn| insn.name == 'ujit_call_example' }
      fileoff = get_fileoff
      tc_table_offset = get_symbol_offset('vm_exec_core.insns_address_table')
      vm_exec_core_offset = get_symbol_offset('vm_exec_core')
      p instruction_id if $DEBUG
      p fileoff if $DEBUG
      p tc_table_offset.to_s(16) if $DEBUG
      offset_to_insn_in_tc_table = fileoff + tc_table_offset + 8 * instruction_id
      p offset_to_insn_in_tc_table if $DEBUG
      offset_to_handler_code_from_vm_exec_core = readint8b(offset_to_insn_in_tc_table)
      p offset_to_handler_code_from_vm_exec_core if $DEBUG
      disassemble(vm_exec_core_offset + offset_to_handler_code_from_vm_exec_core)
    end

    def comma_separated_hex_string(nums)
      nums.map{ |byte| '0x'+byte}.join(', ')
    end

    def pre_call_bytes
      scrape unless @pre_call_bytes
      comma_separated_hex_string(@pre_call_bytes)
    end

    def post_call_bytes
      scrape unless @post_call_bytes
      comma_separated_hex_string(@post_call_bytes)
    end
  end
end

require_relative 'micro_jit/example_instructions'
