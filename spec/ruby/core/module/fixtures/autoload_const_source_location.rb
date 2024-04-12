module ConstantSpecs
  BEFORE_DEFINE_LOCATION = const_source_location(:ConstSource)
  module ConstSource
    LOCATION = Object.const_source_location(name)
  end
end
