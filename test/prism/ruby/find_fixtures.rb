# frozen_string_literal: true

# Test fixtures for Prism.find. These must be in a separate file because
# source_location returns the file path and Prism.find re-parses the file.

module Prism
  module FindFixtures
    module Methods
      def simple_method
        42
      end

      def method_with_params(a, b, c)
        a + b + c
      end

      def method_with_block(&block)
        block.call
      end

      def self.singleton_method_fixture
        :singleton
      end

      def été
        :utf8
      end

      def inline_method; :inline; end
    end

    module Procs
      SIMPLE_PROC = proc { 42 }
      SIMPLE_LAMBDA = ->(x) { x * 2 }
      MULTI_LINE_LAMBDA = lambda do |x|
        x + 1
      end
      DO_BLOCK_PROC = proc do |x|
        x - 1
      end
    end

    module DefineMethod
      define_method(:dynamic) { |x| x + 1 }
    end

    module ForLoop
      for_proc = nil
      o = Object.new
      def o.each(&block) = block.call(block)
      for for_proc in o; end
      FOR_PROC = for_proc
    end

    module MultipleOnLine
      def self.first; end; def self.second; end
    end

    module Errors
      def self.divide(a, b)
        a / b
      end

      def self.call_undefined
        undefined_method_call
      end
    end
  end
end
