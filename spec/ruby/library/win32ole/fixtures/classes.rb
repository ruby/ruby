require 'win32ole'

module WIN32OLESpecs
  WIN32OLERuntimeError ||= WIN32OLE::RuntimeError
  WIN32OLE_TYPELIB ||= WIN32OLE::TypeLib

  MSXML_AVAILABLE = WIN32OLE_TYPELIB.typelibs.any? { |t| t.name.start_with?('Microsoft XML') }
  SYSTEM_MONITOR_CONTROL_AVAILABLE = WIN32OLE_TYPELIB.typelibs.any? { |t| t.name.start_with?('System Monitor Control') }

  def self.new_ole(name)
    tries = 0
    begin
      WIN32OLE.new(name)
    rescue WIN32OLERuntimeError => e
      if tries < 3
        tries += 1
        $stderr.puts "WIN32OLESpecs#new_ole retry (#{tries}): #{e.class}: #{e.message}"
        sleep(2 ** tries)
        retry
      else
        raise
      end
    end
  end
end
