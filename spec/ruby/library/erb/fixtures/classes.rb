module ERBSpecs
  def self.new_erb(input, trim_mode: nil)
    ERB.new(input, trim_mode: trim_mode)
  end
end
