require 'mspec/guards/version'

if RUBY_ENGINE == "ruby"
  def Warning.warn(message)
    # Suppress any warning inside the method to prevent recursion
    verbose = $VERBOSE
    $VERBOSE = nil

    if Thread.current[:in_mspec_complain_matcher]
      return $stderr.write(message)
    end

    case message
    # $VERBOSE = true warnings
    when /(.+\.rb):(\d+):.+possibly useless use of (<|<=|==|>=|>) in void context/
      # Make sure there is a .should otherwise it is missing
      line_nb = Integer($2)
      unless File.exist?($1) and /\.should(_not)? (<|<=|==|>=|>)/ === File.readlines($1)[line_nb-1]
        $stderr.write message
      end
    when /possibly useless use of (\+|-) in void context/
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
    when /enumerator\/(new_spec|initialize_spec)\.rb:\d+: warning: Enumerator\.new without a block is deprecated/
    when /Pattern matching is experimental, and the behavior may change in future versions of Ruby!/
    else
      $stderr.write message
    end
  ensure
    $VERBOSE = verbose
  end
else
  $VERBOSE = nil unless ENV['OUTPUT_WARNINGS']
end
