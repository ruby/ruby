require 'win32ole'

# win32ole deprecated constants like WIN32OLE_TYPELIB in Ruby 3.4
# but only added the replacements like WIN32OLE::TypeLib in Ruby 3.4.
# So we use the new-style constants in specs to avoid deprecation warnings
# and we define the new-style constants as the old ones if they don't exist yet.
WIN32OLE::TypeLib ||= WIN32OLE_TYPELIB
WIN32OLE::RuntimeError ||= WIN32OLERuntimeError
WIN32OLE::Method ||= WIN32OLE_METHOD
WIN32OLE::Type ||= WIN32OLE_TYPE
WIN32OLE::Event ||= WIN32OLE_EVENT
WIN32OLE::Param ||= WIN32OLE_PARAM

module WIN32OLESpecs
  MSXML_AVAILABLE = WIN32OLE::TypeLib.typelibs.any? { |t| t.name.start_with?('Microsoft XML') }
  SYSTEM_MONITOR_CONTROL_AVAILABLE = WIN32OLE::TypeLib.typelibs.any? { |t| t.name.start_with?('System Monitor Control') }

  def self.new_ole(name)
    tries = 0
    begin
      WIN32OLE.new(name)
    rescue WIN32OLE::RuntimeError => e
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
