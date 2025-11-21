# frozen_string_literal: true

class NS_A
  VERSION = "1.2.0"

  def yay
    "yay #{VERSION}"
  end
end

module NS_B
  VERSION = "1.2.0"

  def self.yay
    "yay_b1"
  end
end
