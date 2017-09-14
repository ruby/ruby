require 'mspec/guards/version'

if RUBY_ENGINE == "ruby" and RUBY_VERSION >= "2.4.0"
  ruby_version_is "2.4"..."2.5" do
    # Kernel#warn does not delegate to Warning.warn in 2.4
    module Kernel
      remove_method :warn
      def warn(*messages)
        return if $VERBOSE == nil or messages.empty?
        msg = messages.join("\n")
        msg += "\n" unless msg.end_with?("\n")
        Warning.warn(msg)
      end
      private :warn
    end
  end

  def Warning.warn(message)
    case message
    # $VERBOSE = true warnings
    when /possibly useless use of (<|<=|==|>=|>|\+|-) in void context/
    when /assigned but unused variable/
    when /method redefined/
    when /previous definition of/
    when /instance variable @.+ not initialized/
    when /statement not reached/
    when /shadowing outer local variable/
    when /setting Encoding.default_(in|ex)ternal/
    when /unknown (un)?pack directive/
    when /(un)?trust(ed\?)? is deprecated/
    when /\.exists\? is a deprecated name/
    when /Float .+ out of range/
    when /passing a block to String#(bytes|chars|codepoints|lines) is deprecated/
    when /core\/string\/modulo_spec\.rb:\d+: warning: too many arguments for format string/
    when /regexp\/shared\/new_ascii(_8bit)?\.rb:\d+: warning: Unknown escape .+ is ignored/

    # $VERBOSE = false warnings
    when /constant ::(Fixnum|Bignum) is deprecated/
    when /\/(argf|io|stringio)\/.+(ARGF|IO)#(lines|chars|bytes|codepoints) is deprecated/
    when /Thread\.exclusive is deprecated.+\n.+thread\/exclusive_spec\.rb/
    when /hash\/shared\/index\.rb:\d+: warning: Hash#index is deprecated; use Hash#key/
    when /env\/shared\/key\.rb:\d+: warning: ENV\.index is deprecated; use ENV\.key/
    when /exponent(_spec)?\.rb:\d+: warning: in a\*\*b, b may be too big/
    when /enumerator\/(new|initialize_spec)\.rb:\d+: warning: Enumerator\.new without a block is deprecated/
    else
      $stderr.write message
    end
  end
else
  $VERBOSE = nil unless ENV['OUTPUT_WARNINGS']
end
