require 'rbconfig'

# TODO: replace with IO.popen using array-style arguments in Rake 11
require 'open3'

module Rake

  # Based on a script at:
  #   http://stackoverflow.com/questions/891537/ruby-detect-number-of-cpus-installed
  class CpuCounter # :nodoc: all
    def self.count
      new.count_with_default
    end

    def count_with_default(default=4)
      count || default
    rescue StandardError
      default
    end

    def count
      if defined?(Java::Java)
        count_via_java_runtime
      else
        case RbConfig::CONFIG['host_os']
        when /darwin9/
          count_via_hwprefs_cpu_count
        when /darwin/
          count_via_hwprefs_thread_count || count_via_sysctl
        when /linux/
          count_via_cpuinfo
        when /bsd/
          count_via_sysctl
        when /mswin|mingw/
          count_via_win32
        else
          # Try everything
          count_via_win32 ||
            count_via_sysctl ||
            count_via_hwprefs_thread_count ||
            count_via_hwprefs_cpu_count ||
            count_via_cpuinfo
        end
      end
    end

    begin
      require 'etc'
    rescue LoadError
    else
      if Etc.respond_to?(:nprocessors)
        undef count
        def count
          return Etc.nprocessors
        end
      end
    end

    def count_via_java_runtime
      Java::Java.lang.Runtime.getRuntime.availableProcessors
    rescue StandardError
      nil
    end

    def count_via_win32
      require 'win32ole'
      wmi = WIN32OLE.connect("winmgmts://")
      cpu = wmi.ExecQuery("select NumberOfCores from Win32_Processor") # TODO count hyper-threaded in this
      cpu.to_enum.first.NumberOfCores
    rescue StandardError, LoadError
      nil
    end

    def count_via_cpuinfo
      open('/proc/cpuinfo') { |f| f.readlines }.grep(/processor/).size
    rescue StandardError
      nil
    end

    def count_via_hwprefs_thread_count
      run 'hwprefs', 'thread_count'
    end

    def count_via_hwprefs_cpu_count
      run 'hwprefs', 'cpu_count'
    end

    def count_via_sysctl
      run 'sysctl', '-n', 'hw.ncpu'
    end

    def run(command, *args)
      cmd = resolve_command(command)
      if cmd
        Open3.popen3 cmd, *args do |inn, out, err,|
          inn.close
          err.read
          out.read.to_i
        end
      else
        nil
      end
    end

    def resolve_command(command)
      look_for_command("/usr/sbin", command) ||
        look_for_command("/sbin", command) ||
        in_path_command(command)
    end

    def look_for_command(dir, command)
      path = File.join(dir, command)
      File.exist?(path) ? path : nil
    end

    def in_path_command(command)
      Open3.popen3 'which', command do |_, out,|
        out.eof? ? nil : command
      end
    end
  end
end
