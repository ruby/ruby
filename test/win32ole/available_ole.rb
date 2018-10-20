begin
  require 'win32ole'
rescue LoadError
end

if defined?(WIN32OLE)
  module AvailableOLE
    module_function

    def sysmon_available?
      WIN32OLE_TYPE.new('System Monitor Control', 'SystemMonitor')
      true
    rescue
      false
    end
  end
end
