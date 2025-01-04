class Hash
  # call-seq:
  #   Hash.new(default_value = nil, capacity: 0)
  #   Hash.new(capacity: 0) {|self, key| ... } -> new_hash
  #
  # Returns a new empty \Hash object;
  # initializes the values of Hash#default and Hash#default_proc,
  # which determine the value to be returned by method Hash::[] when the entry does not exist.
  #
  # With no block given, initializes Hash#default to the given +default_value+,
  # and Hash#default_proc to +nil+:
  #
  #   h = Hash.new        # => {}
  #   h.default           # => nil
  #   h.default_proc      # => nil
  #   h = Hash.new(false) # => {}
  #   h.default           # => false
  #
  # With a block given, initializes Hash#default to +nil+,
  # and Hash#default_proc to a new Proc containing the block's code:
  #
  #   h = Hash.new {|hash, key| "Hash #{hash}: Default value for #{key}" }
  #   h.default      # => nil
  #   h.default_proc # => #<Proc:0x00000289b6fa7048 (irb):185>
  #   h[:nosuch]     # => "Hash {}: Default value for nosuch"
  #
  # If optional keyword argument +capacity+ is given with a positive integer value +n+,
  # initializes the hash with enough capacity to accommodate +n+ keys without resizing.
  #
  # Raises ArgumentError if both +default_value+ and a block are given.
  #
  # See also [Methods for Creating a Hash](rdoc-ref:Hash@Methods+for+Creating+a+Hash).
  def initialize(ifnone = (ifnone_unset = true), capacity: 0, &block)
    Primitive.rb_hash_init(capacity, ifnone_unset, ifnone, block)
  end
end
