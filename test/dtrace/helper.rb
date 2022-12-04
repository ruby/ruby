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

impl = :dtrace

# GNU/Linux distros with Systemtap support allows unprivileged users
# in the stapusr and statdev groups to work.
if RUBY_PLATFORM =~ /linux/
  impl = :stap
  begin
    require 'etc'
    ok = (%w[stapusr stapdev].map {|g|(Etc.getgrnam(g) || raise(ArgumentError)).gid} & Process.groups).size == 2
  rescue LoadError, ArgumentError
  end unless ok
end

if ok
  case RUBY_PLATFORM
  when /darwin/i
    begin
      require 'pty'
    rescue LoadError
    end
  end
end

# use miniruby to reduce the amount of trace data we don't care about
rubybin = "miniruby#{RbConfig::CONFIG["EXEEXT"]}"
rubybin = File.join(File.dirname(EnvUtil.rubybin), rubybin)
rubybin = EnvUtil.rubybin unless File.executable?(rubybin)

# make sure ruby was built with --enable-dtrace and we can run
# dtrace(1) or stap(1):
cmd = "#{rubybin} --disable=gems -eexit"
case impl
when :dtrace; cmd = %W(dtrace -l -n ruby$target:::gc-sweep-end -c #{cmd})
when :stap; cmd = %W(stap -l process.mark("gc__sweep__end") -c #{cmd})
else
  warn "don't know how to check if built with #{impl} support"
  cmd = false
end

NEEDED_ENVS = [RbConfig::CONFIG["LIBPATHENV"], "RUBY", "RUBYOPT"].compact

if cmd and ok
  sudocmd = []
  if sudo
    sudocmd << sudo
    NEEDED_ENVS.each {|name| val = ENV[name] and sudocmd << "#{name}=#{val}"}
  end
  ok = system(*sudocmd, *cmd, err: IO::NULL, out: IO::NULL)
end

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
      end if defined?(PTY)
    end

    # only handles simple cases, use a Hash for d_program
    # if there are more complex cases
    def dtrace2systemtap(d_program)
      translate = lambda do |str|
        # dtrace starts args with '0', systemtap with '1' and prefixes '$'
        str = str.gsub(/\barg(\d+)/) { "$arg#{$1.to_i + 1}" }
        # simple function mappings:
        str.gsub!(/\bcopyinstr\b/, 'user_string')
        str.gsub!(/\bstrstr\b/, 'isinstr')
        str
      end
      out = ''
      cond = nil
      d_program.split(/^/).each do |l|
        case l
        when /\bruby\$target:::([a-z-]+)/
          name = $1.gsub(/-/, '__')
          out << %Q{probe process.mark("#{name}")\n}
        when %r{/(.+)/}
          cond = translate.call($1)
        when "{\n"
          out << l
          out << "if (#{cond}) {\n" if cond
        when "}\n"
          out << "}\n" if cond
          out << l
        else
          out << translate.call(l)
        end
      end
      out
    end

    DTRACE_CMD ||= %w[dtrace]

    READ_PROBES ||= proc do |cmd|
      IO.popen(cmd, err: [:child, :out], &:readlines)
    end

    def trap_probe d_program, ruby_program
      if Hash === d_program
        d_program = d_program[IMPL] or
          omit "#{d_program} not implemented for #{IMPL}"
      elsif String === d_program && IMPL == :stap
        d_program = dtrace2systemtap(d_program)
      end
      d = Tempfile.new(%w'probe .d')
      d.write d_program
      d.flush

      rb = Tempfile.new(%w'probed .rb')
      rb.write ruby_program
      rb.flush

      d_path  = d.path
      rb_path = rb.path
      cmd = "#{RUBYBIN} --disable=gems -I#{INCLUDE} #{rb_path}"
      if IMPL == :stap
        cmd = %W(stap #{d_path} -c #{cmd})
      else
        cmd = [*DTRACE_CMD, "-q", "-s", d_path, "-c", cmd ]
      end
      if sudo = @@sudo
        NEEDED_ENVS.each do |name|
          if val = ENV[name]
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
  DTrace::TestCase.const_set(:IMPL, impl)
  DTrace::TestCase.const_set(:RUBYBIN, rubybin)
end
