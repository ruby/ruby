# for proc.c

class Module
  #  call-seq:
  #     mod.instance_method(symbol)   -> unbound_method
  #
  #  Returns an +UnboundMethod+ representing the given
  #  instance method in _mod_.
  #
  #     class Interpreter
  #       def do_a() print "there, "; end
  #       def do_d() print "Hello ";  end
  #       def do_e() print "!\n";     end
  #       def do_v() print "Dave";    end
  #       Dispatcher = {
  #         "a" => instance_method(:do_a),
  #         "d" => instance_method(:do_d),
  #         "e" => instance_method(:do_e),
  #         "v" => instance_method(:do_v)
  #       }
  #       def interpret(string)
  #         string.each_char {|b| Dispatcher[b].bind(self).call }
  #       end
  #     end
  #
  #     interpreter = Interpreter.new
  #     interpreter.interpret('dave')
  #
  #  <em>produces:</em>
  #
  #     Hello there, Dave!
  #
  def instance_method(method_name, inherit=true)
    __builtin_mod_instance_method(method_name, inherit)
  end

  #  call-seq:
  #     mod.public_instance_method(symbol)   -> unbound_method
  #
  #  Similar to _instance_method_, searches public method only.
  #
  def public_instance_method(method_name, inherit=true)
    __builtin_mod_public_instance_method(method_name, inherit)
  end
end
