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
if ok
  case RUBY_PLATFORM
  when /darwin/i
    begin
      require 'pty'
    rescue LoadError
      ok = false
    end
  end
end
ok &= (`dtrace -V` rescue false)
module DTrace
  class TestCase < Test::Unit::TestCase
    INCLUDE = File.expand_path('..', File.dirname(__FILE__))

    case RUBY_PLATFORM
    when /solaris/i
      # increase bufsize to 8m (default 4m on Solaris)
      DTRACE_CMD = %w[dtrace -b 8m]
    when /darwin/i
      READ_PROBES = proc do |cmd|
        lines = nil
        PTY.spawn(*cmd) do |io, _, pid|
          lines = io.readlines.each {|line| line.sub!(/\r$/, "")}
          Process.wait(pid)
        end
        lines
      end
    end

    DTRACE_CMD ||= %w[dtrace]

    READ_PROBES ||= proc do |cmd|
      IO.popen(cmd, err: [:child, :out], &:readlines)
    end

    exeext = Regexp.quote(RbConfig::CONFIG["EXEEXT"])
    RUBYBIN = EnvUtil.rubybin.sub(/\/ruby-runner(?=#{exeext}\z)/, '/miniruby')

    def trap_probe d_program, ruby_program
      d = Tempfile.new(%w'probe .d')
      d.write d_program
      d.flush

      rb = Tempfile.new(%w'probed .rb')
      rb.write ruby_program
      rb.flush

      d_path  = d.path
      rb_path = rb.path

      cmd = [*DTRACE_CMD, "-q", "-s", d_path, "-c", "#{RUBYBIN} -I#{INCLUDE} #{rb_path}"]
      if sudo = @@sudo
        [RbConfig::CONFIG["LIBPATHENV"], "RUBY", "RUBYOPT"].each do |name|
          if name and val = ENV[name]
            cmd.unshift("#{name}=#{val}")
          end
        end
        cmd.unshift(sudo)
      end
      probes = READ_PROBES.(cmd)
      d.close(true)
      rb.close(true)
      yield(d_path, rb_path, probes)
    end
  end
end if ok

if ok
  DTrace::TestCase.class_variable_set(:@@sudo, sudo)
end
