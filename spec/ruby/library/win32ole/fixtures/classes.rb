module WIN32OLESpecs
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
