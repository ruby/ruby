module Marshal
  # call-seq:
  #     load( source [, proc] ) -> obj
  #     restore( source [, proc] ) -> obj
  #
  # Returns the result of converting the serialized data in source into a
  # Ruby object (possibly with associated subordinate objects). source
  # may be either an instance of IO or an object that responds to
  # to_str. If proc is specified, each object will be passed to the proc, as the object
  # is being deserialized.
  #
  # Never pass untrusted data (including user supplied input) to this method.
  # Please see the overview for further details.
  def self.load(source, proc = nil, freeze: false)
    Primitive.marshal_load(source, proc, freeze)
  end

  class << self
    alias restore load
  end
end
