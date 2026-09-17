module MSpec
  FATAL_DEPRECATION = ENV['MSPEC_FATAL_DEPRECATION']

  def self.deprecate(what, replacement)
    user_caller = caller.find { |line| !line.include?('lib/mspec') }
    message = "\n#{what} is deprecated, use #{replacement} instead.\nfrom #{user_caller}"
    $stderr.puts message
    raise SpecExpectationNotMetError, message if FATAL_DEPRECATION
  end
end
