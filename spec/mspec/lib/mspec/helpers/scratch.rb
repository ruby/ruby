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

  def self.inspect
    "<ScratchPad @record=#{@record.inspect}>"
  end
end
