module ScratchPad
  def self.clear
    @record = nil
  end

  def self.record(arg)
    @record = arg
  end

  def self.<<(arg)
    @record << arg
  end

  def self.recorded
    @record
  end
end
