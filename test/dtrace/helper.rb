# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'
require 'tempfile'

if Process.euid == 0
  ok = true
elsif (sudo = ENV["SUDO"]) and !sudo.empty? and (`#{sudo} echo ok` rescue false)
  ok = true
else
  ok = false
end
ok &= (`dtrace -V` rescue false)
module DTrace
  class TestCase < Test::Unit::TestCase
    INCLUDE = File.expand_path('..', File.dirname(__FILE__))

    def trap_probe d_program, ruby_program
      d = Tempfile.new(%w'probe .d')
      d.write d_program
      d.flush

      rb = Tempfile.new(%w'probed .rb')
      rb.write ruby_program
      rb.flush

      d_path  = d.path
      rb_path = rb.path

      case RUBY_PLATFORM
      when /solaris/i
        # increase bufsize to 8m (default 4m on Solaris)
        cmd = [ "dtrace", "-b", "8m" ]
      else
        cmd = [ "dtrace" ]
      end

      cmd.concat [ "-q", "-s", d_path, "-c", "#{EnvUtil.rubybin} -I#{INCLUDE} #{rb_path}"]
      if sudo = @@sudo
        [RbConfig::CONFIG["LIBPATHENV"], "RUBY", "RUBYOPT"].each do |name|
          if name and val = ENV[name]
            cmd.unshift("#{name}=#{val}")
          end
        end
        cmd.unshift(sudo)
      end
      probes = IO.popen(cmd, err: [:child, :out]) do |io|
        io.readlines
      end
      d.close(true)
      rb.close(true)
      yield(d_path, rb_path, probes)
    end
  end
end if ok

if ok
  DTrace::TestCase.class_variable_set(:@@sudo, sudo)
end
