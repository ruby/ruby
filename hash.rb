class Hash
  # call-seq:
  #   Hash.new(default_value = nil, capacity: 0) -> new_hash
  #   Hash.new(capacity: 0) {|self, key| ... } -> new_hash
  #
  # Returns a new empty \Hash object.
  #
  # Initializes the values of Hash#default and Hash#default_proc,
  # which determine the behavior when a given key is not found;
  # see {Key Not Found?}[rdoc-ref:Hash@Key+Not+Found-3F].
  #
  # By default, a hash has +nil+ values for both +default+ and +default_proc+:
  #
  #   h = Hash.new        # => {}
  #   h.default           # => nil
  #   h.default_proc      # => nil
  #
  # With argument +default_value+ given, sets the +default+ value for the hash:
  #
  #   h = Hash.new(false) # => {}
  #   h.default           # => false
  #   h.default_proc      # => nil
  #
  # With a block given, sets the +default_proc+ value:
  #
  #   h = Hash.new {|hash, key| "Hash #{hash}: Default value for #{key}" }
  #   h.default      # => nil
  #   h.default_proc # => #<Proc:0x00000289b6fa7048 (irb):185>
  #   h[:nosuch]     # => "Hash {}: Default value for nosuch"
  #
  # Raises ArgumentError if both +default_value+ and a block are given.
  #
  # If optional keyword argument +capacity+ is given with a positive integer value +n+,
  # initializes the hash with enough capacity to accommodate +n+ entries without resizing.
  #
  # See also {Methods for Creating a Hash}[rdoc-ref:Hash@Methods+for+Creating+a+Hash].
  def initialize(ifnone = (ifnone_unset = true), capacity: 0, &block)
    Primitive.rb_hash_init(capacity, ifnone_unset, ifnone, block)
  end
end
