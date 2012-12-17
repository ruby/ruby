# -*- coding: us-ascii -*-
require 'minitest/autorun'
require 'tempfile'
require_relative '../ruby/envutil'

if Process.euid == 0
  ok = true
elsif (sudo = ENV["SUDO"]) and (`#{sudo} echo ok` rescue false)
  ok = true
else
  ok = false
end
ok &= (`dtrace -V` rescue false)
module DTrace
  class TestCase < MiniTest::Unit::TestCase
    INCLUDE = File.expand_path(File.join(File.dirname(__FILE__), '..'))

    def trap_probe d_program, ruby_program
      d = Tempfile.new('probe.d')
      d.write d_program
      d.flush

      rb = Tempfile.new('probed.rb')
      rb.write ruby_program
      rb.flush

      d_path  = d.path
      rb_path = rb.path

      cmd = ["dtrace", "-q", "-s", d_path, "-c", "#{EnvUtil.rubybin} -I#{INCLUDE} #{rb_path}"]
      sudo = ENV["SUDO"] and cmd.unshift(sudo)
      probes = IO.popen(cmd) do |io|
        io.readlines
      end
      d.close(true)
      rb.close(true)
      yield(d_path, rb_path, probes)
    end
  end
end if ok
