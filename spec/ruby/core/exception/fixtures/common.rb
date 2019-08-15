module ExceptionSpecs
  class Exceptional < Exception; end

  class Backtrace
    def self.backtrace
      begin
        raise # If you move this line, update backtrace_spec.rb
      rescue RuntimeError => e
        e.backtrace
      end
    end

    def self.backtrace_locations
      begin
        raise
      rescue RuntimeError => e
        e.backtrace_locations
      end
    end
  end

  class UnExceptional < Exception
    def backtrace
      nil
    end
    def message
      nil
    end
  end

  class ConstructorException < Exception

    def initialize
    end

  end

  class OverrideToS < RuntimeError
    def to_s
      "this is from #to_s"
    end
  end

  class EmptyToS < RuntimeError
    def to_s
      ""
    end
  end

  class InitializeException < StandardError
    attr_reader :ivar

    def initialize(message = nil)
      super
      @ivar = 1
    end

    def initialize_copy(other)
      super
      ScratchPad.record object_id
    end
  end

  module ExceptionModule
    def repr
      1
    end
  end
end

module NoMethodErrorSpecs
  class NoMethodErrorA; end

  class NoMethodErrorB; end

  class NoMethodErrorC;
    protected
    def a_protected_method;end
    private
    def a_private_method; end
  end

  class NoMethodErrorD; end

  class InstanceException < Exception
  end
end

class NameErrorSpecs
  class ReceiverClass
    def call_undefined_class_variable
      @@doesnt_exist
    end
  end
end
