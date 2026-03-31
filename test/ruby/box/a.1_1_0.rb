# frozen_string_literal: true

class BOX_A
  VERSION = "1.1.0"

  def yay
    "yay #{VERSION}"
  end
end

module BOX_B
  VERSION = "1.1.0"

  def self.yay
    "yay_b1"
  end
end
