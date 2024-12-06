class Reline::KeyActor::Base
  def initialize(mappings = nil)
    @matching_bytes = {}
    @key_bindings = {}
    add_mappings(mappings) if mappings
  end

  def add_mappings(mappings)
    add([27], :ed_ignore)
    128.times do |key|
      func = mappings[key]
      meta_func = mappings[key | 0b10000000]
      add([key], func) if func
      add([27, key], meta_func) if meta_func
    end
  end

  def add(key, func)
    (1...key.size).each do |size|
      @matching_bytes[key.take(size)] = true
    end
    @key_bindings[key] = func
  end

  def matching?(key)
    @matching_bytes[key]
  end

  def get(key)
    @key_bindings[key]
  end

  def clear
    @matching_bytes.clear
    @key_bindings.clear
  end
end
