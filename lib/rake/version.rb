module Rake
  VERSION = '0.9.2.1'

  module Version # :nodoc: all
    MAJOR, MINOR, BUILD = VERSION.split '.'
    NUMBERS = [ MAJOR, MINOR, BUILD ]
  end
end
