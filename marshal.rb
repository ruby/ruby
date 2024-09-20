module Marshal
  # call-seq:
  #    load(source, proc = nil, freeze: false) -> obj
  #    restore(source, proc = nil, freeze: false) -> obj
  #
  # Returns the result of converting the serialized data in source into a
  # Ruby object (possibly with associated subordinate objects). source
  # may be either an instance of IO or an object that responds to
  # to_str. If proc is specified, each object will be passed to the proc, as the object
  # is being deserialized.
  #
  # Never pass untrusted data (including user supplied input) to this method.
  # Please see the overview for further details.
  #
  # If the <tt>freeze: true</tt> argument is passed, deserialized object would
  # be deeply frozen. Note that it may lead to more efficient memory usage due to
  # frozen strings deduplication:
  #
  #    serialized = Marshal.dump(['value1', 'value2', 'value1', 'value2'])
  #
  #    deserialized = Marshal.load(serialized)
  #    deserialized.map(&:frozen?)
  #    # => [false, false, false, false]
  #    deserialized.map(&:object_id)
  #    # => [1023900, 1023920, 1023940, 1023960] -- 4 different objects
  #
  #    deserialized = Marshal.load(serialized, freeze: true)
  #    deserialized.map(&:frozen?)
  #    # => [true, true, true, true]
  #    deserialized.map(&:object_id)
  #    # => [1039360, 1039380, 1039360, 1039380] -- only 2 different objects, object_ids repeating
  #
  def self.load(source, proc = nil, freeze: false)
    Primitive.marshal_load(source, proc, freeze)
  end

  class << self
    alias restore load
  end
end
