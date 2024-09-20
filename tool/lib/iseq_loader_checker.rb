# frozen_string_literal: true

begin
  require '-test-/iseq_load/iseq_load'
rescue LoadError
end
require 'tempfile'

class RubyVM::InstructionSequence
  def disasm_if_possible
    begin
      self.disasm
    rescue Encoding::CompatibilityError, EncodingError, SecurityError
      nil
    end
  end

  def self.compare_dump_and_load i1, dumper, loader
    dump = dumper.call(i1)
    return i1 unless dump
    i2 = loader.call(dump)

    # compare disassembled result
    d1 = i1.disasm_if_possible
    d2 = i2.disasm_if_possible

    if d1 != d2
      STDERR.puts "expected:"
      STDERR.puts d1
      STDERR.puts "actual:"
      STDERR.puts d2

      t1 = Tempfile.new("expected"); t1.puts d1; t1.close
      t2 = Tempfile.new("actual"); t2.puts d2; t2.close
      system("diff -u #{t1.path} #{t2.path}") # use diff if available
      exit(1)
    end
    i2
  end

  opt = ENV['RUBY_ISEQ_DUMP_DEBUG']

  if opt && caller.any?{|e| /test\/runner\.rb/ =~ e}
    puts "RUBY_ISEQ_DUMP_DEBUG = #{opt}" if opt
  end

  CHECK_TO_A      = 'to_a'      == opt
  CHECK_TO_BINARY = 'to_binary' == opt

  def self.translate i1
    # check to_a/load_iseq
    compare_dump_and_load(i1,
                                   proc{|iseq|
                                     ary = iseq.to_a
                                     ary[9] == :top ? ary : nil
                                   },
                                   proc{|ary|
                                     RubyVM::InstructionSequence.iseq_load(ary)
                                   }) if CHECK_TO_A && defined?(RubyVM::InstructionSequence.iseq_load)

    # check to_binary
    i2_bin = compare_dump_and_load(i1,
                                   proc{|iseq|
                                     begin
                                       iseq.to_binary
                                     rescue RuntimeError # not a toplevel
                                       # STDERR.puts [:failed, $!, iseq].inspect
                                       nil
                                     end
                                   },
                                   proc{|bin|
                                     iseq = RubyVM::InstructionSequence.load_from_binary(bin)
                                     # STDERR.puts iseq.inspect
                                     iseq
                                   }) if CHECK_TO_BINARY
    # return value
    i2_bin if CHECK_TO_BINARY
  end if CHECK_TO_A || CHECK_TO_BINARY

  if opt == "prism"
    # If RUBY_ISEQ_DUMP_DEBUG is "prism", we'll set up
    # InstructionSequence.load_iseq to intercept loading filepaths to compile
    # using prism.
    def self.load_iseq(filepath)
      RubyVM::InstructionSequence.compile_file_prism(filepath)
    end
  end
end

#require_relative 'x'; exit(1)
