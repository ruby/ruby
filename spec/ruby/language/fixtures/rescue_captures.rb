module RescueSpecs
  class Captor
    attr_accessor :captured_error

    def self.should_capture_exception
      captor = new
      captor.capture('some text').should == :caught # Ensure rescue body still runs
      captor.captured_error.message.should == 'some text'
    end
  end

  class ClassVariableCaptor < Captor
    def capture(msg)
      raise msg
    rescue => @@captured_error
      :caught
    end

    def captured_error
      self.class.remove_class_variable(:@@captured_error)
    end
  end

  class ConstantCaptor < Captor
    # Using lambda gets around the dynamic constant assignment warning
    CAPTURE = -> msg {
      begin
        raise msg
      rescue => CapturedError
        :caught
      end
    }

    def capture(msg)
      CAPTURE.call(msg)
    end

    def captured_error
      self.class.send(:remove_const, :CapturedError)
    end
  end

  class GlobalVariableCaptor < Captor
    def capture(msg)
      raise msg
    rescue => $captured_error
      :caught
    end

    def captured_error
      $captured_error.tap do
        $captured_error = nil # Can't remove globals, only nil them out
      end
    end
  end

  class InstanceVariableCaptor < Captor
    def capture(msg)
      raise msg
    rescue => @captured_error
      :caught
    end
  end

  class LocalVariableCaptor < Captor
    def capture(msg)
      raise msg
    rescue => captured_error
      @captured_error = captured_error
      :caught
    end
  end

  class SafeNavigationSetterCaptor < Captor
    def capture(msg)
      raise msg
    rescue => self&.captured_error
      :caught
    end
  end

  class SetterCaptor < Captor
    def capture(msg)
      raise msg
    rescue => self.captured_error
      :caught
    end
  end

  class SquareBracketsCaptor < Captor
    def capture(msg)
      @hash = {}

      raise msg
    rescue => self[:error]
      :caught
    end

    def []=(key, value)
      @hash[key] = value
    end

    def captured_error
      @hash[:error]
    end
  end
end
