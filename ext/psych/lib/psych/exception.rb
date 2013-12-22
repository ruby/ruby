module Psych
  class Exception < RuntimeError
  end

  class BadAlias < Exception
  end

  class DisallowedClass < Exception
    def initialize klass_name
      super "Tried to load unspecified class: #{klass_name}"
    end
  end
end
