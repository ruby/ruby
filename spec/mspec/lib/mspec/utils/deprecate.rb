module MSpec
  def self.deprecate(what, replacement)
    user_caller = caller.find { |line| !line.include?('lib/mspec') }
    $stderr.puts "\n#{what} is deprecated, use #{replacement} instead.\nfrom #{user_caller}"
  end
end
