module Rake
  module Version
    NUMBERS = [
      MAJOR = 0,
      MINOR = 9,
      BUILD = 2,
    ]
  end
  VERSION = Version::NUMBERS.join('.')
end
