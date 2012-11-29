module Rake
  VERSION = '0.9.5'

  module Version # :nodoc: all
    MAJOR, MINOR, BUILD, = Rake::VERSION.split '.'

    NUMBERS = [
      MAJOR,
      MINOR,
      BUILD,
    ]
  end
end
