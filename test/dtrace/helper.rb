require 'minitest/autorun'
require 'tempfile'

module DTrace
  class TestCase < MiniTest::Unit::TestCase
    INCLUDE = File.expand_path(File.join(File.dirname(__FILE__), '..'))

    def setup
      skip "must be setuid 0 to run dtrace tests" unless Process.euid == 0
    end

    def trap_probe d_program, ruby_program
      d = Tempfile.new('probe.d')
      d.write d_program
      d.flush

      rb = Tempfile.new('probed.rb')
      rb.write ruby_program
      rb.flush

      d_path  = d.path
      rb_path = rb.path

      cmd = "dtrace -q -s #{d_path} -c '#{Gem.ruby} -I#{INCLUDE} #{rb_path}'"
      probes = IO.popen(cmd) do |io|
        io.readlines
      end
      d.close(true)
      rb.close(true)
      yield(d_path, rb_path, probes)
    end
  end
end
