# frozen_string_literal: true
begin
  require '-test-/memory_status.so'
rescue LoadError
end

module Memory
  keys = []

  case
  when File.exist?(procfile = "/proc/self/status") && (pat = /^Vm(\w+):\s+(\d+)/) =~ (data = File.binread(procfile))
    PROC_FILE = procfile
    VM_PAT = pat
    def self.read_status
      IO.foreach(PROC_FILE, encoding: Encoding::ASCII_8BIT) do |l|
        yield($1.downcase.intern, $2.to_i * 1024) if VM_PAT =~ l
      end
    end

    data.scan(pat) {|k, v| keys << k.downcase.intern}

  when /mswin|mingw/ =~ RUBY_PLATFORM
    require 'fiddle/import'
    require 'fiddle/types'

    module Win32
      extend Fiddle::Importer
      dlload "kernel32.dll", "psapi.dll"
      include Fiddle::Win32Types
      typealias "SIZE_T", "size_t"

      PROCESS_MEMORY_COUNTERS = struct [
        "DWORD  cb",
        "DWORD  PageFaultCount",
        "SIZE_T PeakWorkingSetSize",
        "SIZE_T WorkingSetSize",
        "SIZE_T QuotaPeakPagedPoolUsage",
        "SIZE_T QuotaPagedPoolUsage",
        "SIZE_T QuotaPeakNonPagedPoolUsage",
        "SIZE_T QuotaNonPagedPoolUsage",
        "SIZE_T PagefileUsage",
        "SIZE_T PeakPagefileUsage",
      ]

      typealias "PPROCESS_MEMORY_COUNTERS", "PROCESS_MEMORY_COUNTERS*"

      extern "HANDLE GetCurrentProcess()", :stdcall
      extern "BOOL GetProcessMemoryInfo(HANDLE, PPROCESS_MEMORY_COUNTERS, DWORD)", :stdcall

      module_function
      def memory_info
        size = PROCESS_MEMORY_COUNTERS.size
        data = PROCESS_MEMORY_COUNTERS.malloc
        data.cb = size
        data if GetProcessMemoryInfo(GetCurrentProcess(), data, size)
      end
    end

    keys << :peak << :size
    def self.read_status
      if info = Win32.memory_info
        yield :peak, info.PeakPagefileUsage
        yield :size, info.PagefileUsage
      end
    end
  when (require_relative 'find_executable'
        pat = /^\s*(\d+)\s+(\d+)$/
        pscmd = EnvUtil.find_executable("ps", "-ovsz=", "-orss=", "-p", $$.to_s) {|out| pat =~ out})
    pscmd.pop
    PAT = pat
    PSCMD = pscmd

    keys << :size << :rss
    def self.read_status
      if PAT =~ IO.popen(PSCMD + [$$.to_s], "r", err: [:child, :out], &:read)
        yield :size, $1.to_i*1024
        yield :rss, $2.to_i*1024
      end
    end
  else
    def self.read_status
      raise NotImplementedError, "unsupported platform"
    end
  end

  if !keys.empty?
    Status = Struct.new(*keys)
  end
end unless defined?(Memory::Status)

if defined?(Memory::Status)
  class Memory::Status
    def _update
      Memory.read_status do |key, val|
        self[key] = val
      end
    end unless method_defined?(:_update)

    Header = members.map {|k| k.to_s.upcase.rjust(6)}.join('')
    Format = "%6d"

    def initialize
      _update
    end

    def to_s
      status = each_pair.map {|n,v|
        "#{n}:#{v}"
      }
      "{#{status.join(",")}}"
    end

    def self.parse(str)
      status = allocate
      str.scan(/(?:\A\{|\G,)(#{members.join('|')}):(\d+)(?=,|\}\z)/) do
        status[$1] = $2.to_i
      end
      status
    end
  end

  # On some platforms (e.g. Solaris), libc malloc does not return
  # freed memory to OS because of efficiency, and linking with extra
  # malloc library is needed to detect memory leaks.
  #
  case RUBY_PLATFORM
  when /solaris2\.(?:9|[1-9][0-9])/i # Solaris 9, 10, 11,...
    bits = [nil].pack('p').size == 8 ? 64 : 32
    if ENV['LD_PRELOAD'].to_s.empty? &&
        ENV["LD_PRELOAD_#{bits}"].to_s.empty? &&
        (ENV['UMEM_OPTIONS'].to_s.empty? ||
         ENV['UMEM_OPTIONS'] == 'backend=mmap') then
      envs = {
        'LD_PRELOAD' => 'libumem.so',
        'UMEM_OPTIONS' => 'backend=mmap'
      }
      args = [
              envs,
              "--disable=gems",
              "-v", "-",
             ]
      _, err, status = EnvUtil.invoke_ruby(args, "exit(0)", true, true)
      if status.exitstatus == 0 && err.to_s.empty? then
        Memory::NO_MEMORY_LEAK_ENVS = envs
      end
    end
  end #case RUBY_PLATFORM

end
