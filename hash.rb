class Hash
  # call-seq:
  #    Hash.new(default_value = nil) -> new_hash
  #    Hash.new(default_value = nil, capacity: size) -> new_hash
  #    Hash.new {|hash, key| ... } -> new_hash
  #    Hash.new(capacity: size) {|hash, key| ... } -> new_hash
  #
  # Returns a new empty +Hash+ object.
  #
  # The initial default value and initial default proc for the new hash
  # depend on which form above was used. See {Default Values}[rdoc-ref:Hash@Default+Values].
  #
  # If neither an argument nor a block is given,
  # initializes both the default value and the default proc to <tt>nil</tt>:
  #   h = Hash.new
  #   h.default # => nil
  #   h.default_proc # => nil
  #
  # If argument <tt>default_value</tt> is given but no block is given,
  # initializes the default value to the given <tt>default_value</tt>
  # and the default proc to <tt>nil</tt>:
  #   h = Hash.new(false)
  #   h.default # => false
  #   h.default_proc # => nil
  #
  # If a block is given but no <tt>default_value</tt>, stores the block as the default proc
  # and sets the default value to <tt>nil</tt>:
  #   h = Hash.new {|hash, key| "Default value for #{key}" }
  #   h.default # => nil
  #   h.default_proc.class # => Proc
  #   h[:nosuch] # => "Default value for nosuch"
  #
  # If both a block and a <tt>default_value</tt> are given, raises an +ArgumentError+
  #
  # If the optional keyword argument +capacity+ is given, the hash will be allocated
  # with enough capacity to accomodate this many keys without having to be resized.
  def initialize(ifnone = (ifnone_unset = true), capacity: 0, &block)
    Primitive.rb_hash_init(capacity, ifnone_unset, ifnone, block)
  end
end
