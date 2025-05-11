class String
  def yay
    "yay"
  end
end

String.new.yay # check this doesn't raise NoMethodError

module Bar
  def self.yay
    String.new.yay
  end
end
