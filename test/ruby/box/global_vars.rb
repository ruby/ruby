module LineSplitter
  def self.read
    $-0
  end

  def self.write(char)
    $-0 = char
  end
end

module FieldSplitter
  def self.read
    $,
  end

  def self.write(char)
    $, = char
  end
end

module UniqueGvar
  def self.read
    $used_only_in_box
  end

  def self.write(val)
    $used_only_in_box = val
  end

  def self.write_only(val)
    $write_only_var_in_box = val
  end

  def self.gvars_in_box
    global_variables
  end
end
