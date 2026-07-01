# frozen_string_literal: false
require_relative 'helper'

module DTrace
  class TestModularGC < TestCase
    MODULAR_GC_DIR = RbConfig::CONFIG["modular_gc_dir"]
    DLEXT = RbConfig::CONFIG["DLEXT"]
    DEFAULT_GC = MODULAR_GC_DIR && File.join(MODULAR_GC_DIR, "librubygc.default.#{DLEXT}")

    def setup
      super
      omit "Ruby was not configured with --with-modular-gc" if MODULAR_GC_DIR.nil? || MODULAR_GC_DIR.empty?
      omit "default modular GC is not installed" unless DEFAULT_GC && File.file?(DEFAULT_GC)
    end

    %w[
      gc-mark-begin
      gc-mark-end
      gc-sweep-begin
      gc-sweep-end
    ].each do |probe_name|
      define_method(:"test_modular_#{probe_name.gsub(/-/, '_')}") do
        probe = "ruby$target:::#{probe_name} { printf(\"#{probe_name}\\n\"); }"

        trap_probe(probe, ruby_program, env: {"RUBY_GC_LIBRARY" => "default"}) do |_, _, saw|
          assert_operator saw.length, :>, 0
        end
      end
    end

    private

    def ruby_program
      "100000.times { Object.new }"
    end
  end
end if defined?(DTrace::TestCase)
