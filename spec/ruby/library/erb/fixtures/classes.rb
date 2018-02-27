module ERBSpecs
  def self.new_erb(input, trim_mode: nil)
    if ruby_version_is "2.6"
      ERB.new(input, trim_mode: trim_mode)
    else
      ERB.new(input, nil, trim_mode)
    end
  end
end
