# :markup: markdown

class Hash
  # call-seq:
  #   Hash.new(default_value = nil, capacity: 0) {|self, key| ... } -> new_hash
  #
  # Returns a new empty \Hash object;
  # initializes `self.default` to `default_value`,
  # which is the value to be returned by method `#[key]` if the entry does not exist:
  #
  # ```
  # h = Hash.new # => {}
  # h.default    # => nil
  # h[:nosuch]   # => nil
  # ```
  #
  # With no block given, initializes `self.default_proc` to `nil`:
  #
  # ```
  # Hash.new.default_proc # => nil
  # ```
  #
  # With a block given, initializes `self.default_proc` to a new Proc containing the block's code:
  #
  # ```
  # h = Hash.new {|hash, key| "Hash #{hash}: Default value for #{key}" }
  # h.default_proc.class # => Proc
  # h[:nosuch]           # => "Hash {}: Default value for nosuch"
  # ```
  #
  # If optional keyword argument `capacity` is given with a positive integer value `n`,
  # initializes the hash with enough capacity to accommodate `n` keys without having to be resized.
  #
  # Raises ArgumentError if both `default_value` and a block are given.
  #
  # See also [Methods for Creating a Hash](rdoc-ref:Hash@Methods+for+Creating+a+Hash).
  def initialize(ifnone = (ifnone_unset = true), capacity: 0, &block)
    Primitive.rb_hash_init(capacity, ifnone_unset, ifnone, block)
  end
end
