module WIN32OLESpecs
  def self.new_ole(name)
    retries_left = 3
    begin
      WIN32OLE.new(name)
    rescue WIN32OLERuntimeError => e
      if retries_left > 0
        retries_left -= 1
        retry
      else
        raise e
      end
    end
  end
end
