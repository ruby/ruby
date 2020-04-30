# frozen_string_literal: false
require "test/unit"
require "irb"
require "irb/extend-command"

module TestIRB
  class ExtendCommand < Test::Unit::TestCase
    def setup
      @pwd = Dir.pwd
      @tmpdir = File.join(Dir.tmpdir, "test_reline_config_#{$$}")
      begin
        Dir.mkdir(@tmpdir)
      rescue Errno::EEXIST
        FileUtils.rm_rf(@tmpdir)
        Dir.mkdir(@tmpdir)
      end
      Dir.chdir(@tmpdir)
      @home_backup = ENV["HOME"]
      ENV["HOME"] = @tmpdir
    end

    def teardown
      ENV["HOME"] = @home_backup
      Dir.chdir(@pwd)
      FileUtils.rm_rf(@tmpdir)
    end

    def test_irb_info_multiline
      FileUtils.touch("#{@tmpdir}/.inputrc")
      FileUtils.touch("#{@tmpdir}/.irbrc")
      IRB.setup(__FILE__, argv: [])
      IRB.conf[:USE_MULTILINE] = true
      IRB.conf[:USE_SINGLELINE] = false
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion: .+\n
        IRB\sversion:\sirb .+\n
        InputMethod:\sReidlineInputMethod\swith\sReline .+ and .+\n
        \.irbrc\spath: .+
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    end

    def test_irb_info_singleline
      FileUtils.touch("#{@tmpdir}/.inputrc")
      FileUtils.touch("#{@tmpdir}/.irbrc")
      IRB.setup(__FILE__, argv: [])
      IRB.conf[:USE_MULTILINE] = false
      IRB.conf[:USE_SINGLELINE] = true
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion: .+\n
        IRB\sversion:\sirb .+\n
        InputMethod:\sReadlineInputMethod\swith .+ and .+\n
        \.irbrc\spath: .+
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    end

    def test_irb_info_multiline_without_rc_files
      inputrc_backup = ENV["INPUTRC"]
      ENV["INPUTRC"] = "unkown_inpurc"
      ext_backup = IRB::IRBRC_EXT
      IRB.__send__(:remove_const, :IRBRC_EXT)
      IRB.const_set(:IRBRC_EXT, "unkown_ext")
      IRB.setup(__FILE__, argv: [])
      IRB.conf[:USE_MULTILINE] = true
      IRB.conf[:USE_SINGLELINE] = false
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion: .+\n
        IRB\sversion:\sirb .+\n
        InputMethod:\sReidlineInputMethod\swith\sReline\s[^ ]+(?!\sand\s.+)\n
        \z
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    ensure
      ENV["INPUTRC"] = inputrc_backup
      IRB.__send__(:remove_const, :IRBRC_EXT)
      IRB.const_set(:IRBRC_EXT, ext_backup)
    end

    def test_irb_info_singleline_without_rc_files
      inputrc_backup = ENV["INPUTRC"]
      ENV["INPUTRC"] = "unkown_inpurc"
      ext_backup = IRB::IRBRC_EXT
      IRB.__send__(:remove_const, :IRBRC_EXT)
      IRB.const_set(:IRBRC_EXT, "unkown_ext")
      IRB.setup(__FILE__, argv: [])
      IRB.conf[:USE_MULTILINE] = false
      IRB.conf[:USE_SINGLELINE] = true
      workspace = IRB::WorkSpace.new(self)
      irb = IRB::Irb.new(workspace)
      IRB.conf[:MAIN_CONTEXT] = irb.context
      expected = %r{
        Ruby\sversion: .+\n
        IRB\sversion:\sirb .+\n
        InputMethod:\sReadlineInputMethod\swith\s(?~.*\sand\s.+)\n
        \z
      }x
      assert_match expected, irb.context.main.irb_info.to_s
    ensure
      ENV["INPUTRC"] = inputrc_backup
      IRB.__send__(:remove_const, :IRBRC_EXT)
      IRB.const_set(:IRBRC_EXT, ext_backup)
    end
  end
end
