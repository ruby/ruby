module DataSpecs
  guard -> { ruby_version_is "3.2" and Data.respond_to?(:define) } do
    Measure = Data.define(:amount, :unit)
  end
end
