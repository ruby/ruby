# frozen_string_literal: true

require_relative "../spec_helper.rb"

module DeadEnd
  RSpec.describe "exe" do
    def exe_path
      root_dir.join("exe").join("dead_end")
    end

    def exe(cmd)
      out = run!("#{exe_path} #{cmd}")
      puts out if ENV["DEBUG"]
      out
    end

    it "parses valid code" do
      ruby_file = exe_path
      out = exe(ruby_file)
      expect(out.strip).to include("Syntax OK")
    end

    it "parses invalid code" do
      ruby_file = fixtures_dir.join("this_project_extra_def.rb.txt")
      out = exe("#{ruby_file} --no-terminal")

      expect(out.strip).to include("Missing `end` detected")
      expect(out.strip).to include("❯ 36      def filename")
    end

    it "handles heredocs" do
      Tempfile.create do |file|
        lines = fixtures_dir.join("rexe.rb.txt").read.lines
        lines.delete_at(85 - 1)

        Pathname(file.path).write(lines.join)

        out = exe("#{file.path} --no-terminal")

        expect(out).to include(<<~EOM.indent(4))
             16  class Rexe
             40    class Options < Struct.new(
             71    end
          ❯  77    class Lookups
          ❯  78      def input_modes
          ❯ 148    end
            152    class CommandLineParser
            418    end
            551  end
        EOM
      end
    end

    it "records search" do
      Dir.mktmpdir do |dir|
        dir = Pathname(dir)
        tmp_dir = dir.join("tmp").tap(&:mkpath)
        ruby_file = dir.join("file.rb")
        ruby_file.write("def foo\n  end\nend")

        expect(tmp_dir).to be_empty

        out = exe("#{ruby_file} --record #{tmp_dir}")

        expect(out.strip).to include("Unmatched `end` detected")
        expect(tmp_dir).to_not be_empty
      end
    end
  end
end
