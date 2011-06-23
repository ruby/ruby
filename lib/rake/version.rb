module Rake
  VERSION = '0.9.2'

  module Version
    MAJOR, MINOR, BUILD = VERSION.split '.'
    NUMBERS = [ MAJOR, MINOR, BUILD ]
  end
end
