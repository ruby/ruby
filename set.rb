class Set
  def encode_with(coder) # :nodoc:
    coder["hash"] = to_h
  end

  def init_with(coder) # :nodoc:
    replace(coder["hash"].keys)
  end
end
