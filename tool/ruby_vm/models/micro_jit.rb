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
    def target_platform
      # Note, checking RUBY_PLATRFORM doesn't work when cross compiling
      @platform ||= if RUBY_PLATFORM.include?('darwin')
        :darwin
      elsif RUBY_PLATFORM.include?('linux')
        :linux
      else
        :unknown
      end
    end

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

    def get_symbol_section_and_offset(name)
      `objdump -w -t vm.o`.each_line do |line|
        split_line = line.split
        next unless split_line.size >= 6
        # the table should go into a data section
        if split_line[5].include?('insns_address_table') && split_line[3].include?('data')
          p line if $DEBUG
          return [split_line[3], Integer(split_line[0], 16)]
        end
      end
      raise 'Failed to find section and offset for the the instruction address table'
    end

    def get_handler_offset(table_section, table_offset, insn_id)
      target_offset = insn_id * 8 + table_offset
      reloc_start_message = "RELOCATION RECORDS FOR [#{table_section}]:"
      `objdump -w -r vm.o`.each_line do |line|
        line.strip!
        if (line == reloc_start_message)...(line.empty?)
          split_line = line.split
          next if split_line.first == 'RELOCATION'
          next if split_line == ['OFFSET', 'TYPE', 'VALUE']
          if Integer(split_line.first, 16) == target_offset
            section, offset = split_line[2].split('+')
            p line if $DEBUG
            return section, Integer(offset, 16)
          end
        end
      end
      raise 'Failed to find relocation info for the target instruction'
    end

    def objdump_disassemble_command(offset)
      case target_platform
      when :darwin
        "objdump --x86-asm-syntax=intel --start-address=#{offset} --stop-address=#{offset+50} -d vm.o"
      when :linux
        "objdump -M intel --start-address=#{offset} --stop-address=#{offset+50} -d vm.o"
      else
        raise "unkown platform"
      end
    end

    def disassemble(offset)
      command = objdump_disassemble_command(offset)
      puts "Running: #{command}"
      disassembly = `#{command}`
      instructions = []
      puts disassembly if $DEBUG
      disassembly.each_line do |line|
        line = line.strip
        match_data = /\s*\h+:\s*((?:\h\h\s)+)\s+(\w+)/.match(line)
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
      acceptable_mnemonics = %w(mov jmp lea call endbr64)
      unrecognized = nil
      handler_instructions.each { |i| unrecognized = i unless acceptable_mnemonics.include?(i[1]) }
      raise "found an unrecognized \"#{unrecognized[1]}\" instruction in the example. List of recognized instructions: #{acceptable_mnemonics.join(', ')}" if unrecognized
      raise 'found multiple jmp instructions' if handler_instructions.count { |_, mnemonic, _| mnemonic == 'jmp' } > 1
      raise "the jmp instruction seems to be relative which isn't copiable" if instructions[jmp_idx][0].split.size > 4
      raise 'no call instructions found' if handler_instructions.count { |_, mnemonic, _| mnemonic == 'call' } == 0
      raise 'found multiple call instructions' if handler_instructions.count { |_, mnemonic, _| mnemonic == 'call' } > 1
      call_idx = handler_instructions.find_index { |_, mnemonic, _| mnemonic == 'call' }


      pre_call_bytes = []
      post_call_bytes = []

      handler_instructions.take(call_idx).each do |bytes, mnemonic, _|
        pre_call_bytes += bytes.split
      end

      handler_instructions[call_idx + 1, handler_instructions.size].each do |bytes, _, _|
        post_call_bytes += bytes.split
      end

      [pre_call_bytes, post_call_bytes]
    end

    def darwin_scrape(instruction_id)
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

    def linux_scrape(instruction_id)
      table_section, table_offset = get_symbol_section_and_offset('vm_exec_core.insns_address_table')
      p [table_section, table_offset] if $DEBUG
      handler_section, handler_offset = get_handler_offset(table_section, table_offset, instruction_id)
      p [handler_section, handler_offset] if $DEBUG
      disassemble(handler_offset)
    end

    def make_result(success, pre_call, post_call, pre_call_with_ec, post_call_with_ec)
      [success ? 1 : 0,
       [
         ['ujit_pre_call_bytes', comma_separated_hex_string(pre_call)],
         ['ujit_post_call_bytes', comma_separated_hex_string(post_call)],
         ['ujit_pre_call_with_ec_bytes', comma_separated_hex_string(pre_call_with_ec)],
         ['ujit_post_call_with_ec_bytes', comma_separated_hex_string(post_call_with_ec)]
       ]
      ]
    end

    def scrape_instruction(instruction_id)
      raise unless instruction_id.is_a?(Integer)
      case target_platform
      when :darwin
        darwin_scrape(instruction_id)
      when :linux
        linux_scrape(instruction_id)
      else
        raise 'Unkonwn platform. Only Mach-O on macOS and ELF on Linux are supported'
      end
    end

    def scrape
      pre, post = scrape_instruction(RubyVM::Instructions.find_index { |insn| insn.name == 'ujit_call_example' })
      pre_with_ec, post_with_ec = scrape_instruction(RubyVM::Instructions.find_index { |insn| insn.name == 'ujit_call_example_with_ec' })
      make_result(true, pre, post, pre_with_ec, post_with_ec)
    rescue => e
      print_warning("scrape failed: #{e.message}")
      make_result(false, ['cc'], ['cc'], ['cc'], ['cc'])
    end

    def print_warning(text)
      text = "ujit warning: #{text}"
      text = "\x1b[1m#{text}\x1b[0m" if STDOUT.tty?
      STDOUT.puts(text)
    end

    def comma_separated_hex_string(nums)
      nums.map{ |byte| '0x'+byte}.join(', ')
    end
  end
end

require_relative 'micro_jit/example_instructions'
