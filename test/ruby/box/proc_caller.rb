module Bar
  def self.caller(proc_value)
    proc_value.call
  end
end
