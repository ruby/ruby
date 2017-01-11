# :stopdoc:
module Forwardable
  FILE_REGEXP = %r"#{Regexp.quote(File.dirname(__FILE__))}"
  FILTER_EXCEPTION = <<-'END'

        rescue ::Exception
          $@.delete_if {|s| ::Forwardable::FILE_REGEXP =~ s} unless ::Forwardable::debug
          ::Kernel::raise
  END

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
