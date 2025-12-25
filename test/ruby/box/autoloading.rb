# frozen_string_literal: true

autoload :BOX_A, File.join(__dir__, 'a.1_1_0')
BOX_A.new.yay

module BOX_B
  autoload :BAR, File.join(__dir__, 'a')
end
