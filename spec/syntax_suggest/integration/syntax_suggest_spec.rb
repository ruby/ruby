# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe "Integration tests that don't spawn a process (like using the cli)" do
    it "does not timeout on massive files" do
      next unless ENV["SYNTAX_SUGGEST_TIMEOUT"]

      file = fixtures_dir.join("syntax_tree.rb.txt")
      lines = file.read.lines
      lines.delete_at(768 - 1)

      io = StringIO.new

      benchmark = Benchmark.measure do
        debug_perf do
          SyntaxSuggest.call(
            io: io,
            source: lines.join,
            filename: file
          )
        end
        debug_display(io.string)
        debug_display(benchmark)
      end

      expect(io.string).to include(<<~'EOM')
             6  class SyntaxTree < Ripper
           170    def self.parse(source)
           174    end
        >  754    def on_args_add(arguments, argument)
        >  776    class ArgsAddBlock
        >  810    end
          9233  end
      EOM
    end

    it "re-checks all block code, not just what's visible issues/95" do
      file = fixtures_dir.join("ruby_buildpack.rb.txt")
      io = StringIO.new

      debug_perf do
        benchmark = Benchmark.measure do
          SyntaxSuggest.call(
            io: io,
            source: file.read,
            filename: file
          )
        end
        debug_display(io.string)
        debug_display(benchmark)
      end

      expect(io.string).to_not include("def ruby_install_binstub_path")
      expect(io.string).to include(<<~'EOM')
        > 1067    def add_yarn_binary
        > 1068      return [] if yarn_preinstalled?
        > 1069  |
        > 1075    end
      EOM
    end

    it "returns good results on routes.rb" do
      source = fixtures_dir.join("routes.rb.txt").read

      io = StringIO.new
      SyntaxSuggest.call(
        io: io,
        source: source
      )
      debug_display(io.string)

      expect(io.string).to include(<<~'EOM')
           1  Rails.application.routes.draw do
        > 113    namespace :admin do
        > 116    match "/foobar(*path)", via: :all, to: redirect { |_params, req|
        > 120    }
          121  end
      EOM
    end

    it "handles multi-line-methods issues/64" do
      source = fixtures_dir.join("webmock.rb.txt").read

      io = StringIO.new
      SyntaxSuggest.call(
        io: io,
        source: source
      )
      debug_display(io.string)

      expect(io.string).to include(<<~'EOM')
           1  describe "webmock tests" do
          22    it "body" do
          27      query = Cutlass::FunctionQuery.new(
        > 28        port: port
        > 29        body: body
          30      ).call
          34    end
          35  end
      EOM
    end

    it "handles derailed output issues/50" do
      source = fixtures_dir.join("derailed_require_tree.rb.txt").read

      io = StringIO.new
      SyntaxSuggest.call(
        io: io,
        source: source
      )
      debug_display(io.string)

      expect(io.string).to include(<<~'EOM')
           5  module DerailedBenchmarks
           6    class RequireTree
           7      REQUIRED_BY = {}
           9      attr_reader   :name
          10      attr_writer   :cost
        > 13      def initialize(name)
        > 18      def self.reset!
        > 25      end
          73    end
          74  end
      EOM
    end

    it "handles heredocs" do
      lines = fixtures_dir.join("rexe.rb.txt").read.lines
      lines.delete_at(85 - 1)
      io = StringIO.new
      SyntaxSuggest.call(
        io: io,
        source: lines.join
      )

      out = io.string
      debug_display(out)

      expect(out).to include(<<~EOM)
           16  class Rexe
        >  77    class Lookups
        >  78      def input_modes
        > 148    end
          551  end
      EOM
    end

    it "rexe" do
      lines = fixtures_dir.join("rexe.rb.txt").read.lines
      lines.delete_at(148 - 1)
      source = lines.join

      io = StringIO.new
      SyntaxSuggest.call(
        io: io,
        source: source
      )
      out = io.string
      expect(out).to include(<<~EOM)
           16  class Rexe
           18    VERSION = '1.5.1'
        >  77    class Lookups
        > 140      def format_requires
        > 148    end
          551  end
      EOM
    end

    it "ambiguous end" do
      source = <<~'EOM'
        def call          # 0
            print "lol"   # 1
          end # one       # 2
        end # two         # 3
      EOM
      io = StringIO.new
      SyntaxSuggest.call(
        io: io,
        source: source
      )
      out = io.string
      expect(out).to include(<<~EOM)
        > 1  def call          # 0
        > 3    end # one       # 2
        > 4  end # two         # 3
      EOM
    end

    it "simple regression" do
      source = <<~'EOM'
        class Dog
          def bark
            puts "woof"
        end
      EOM
      io = StringIO.new
      SyntaxSuggest.call(
        io: io,
        source: source
      )
      out = io.string
      expect(out).to include(<<~EOM)
        > 1  class Dog
        > 2    def bark
        > 4  end
      EOM
    end
  end
end
