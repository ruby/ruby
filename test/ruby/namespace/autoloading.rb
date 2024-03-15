# frozen_string_literal: true

autoload :NS_A, File.join(__dir__, 'a.1_1_0')
NS_A.new.yay

module NS_B
  autoload :BAR, File.join(__dir__, 'a')
end
