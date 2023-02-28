module DataSpecs
  ruby_version_is "3.2" do
    Measure = Data.define(:amount, :unit)
  end
end
