module Forwardable
  # :stopdoc:

  def self._valid_method?(method)
    catch {|tag|
      eval("BEGIN{throw tag}; ().#{method}", binding, __FILE__, __LINE__)
    }
  rescue SyntaxError
    false
  else
    true
  end

  def self._compile_method(src, file, line)
    eval(src, nil, file, line)
  end
end
