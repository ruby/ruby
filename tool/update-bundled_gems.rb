#!ruby -alpF\s+|#.*
BEGIN {
  require 'rubygems'
  date = nil
  # STDOUT is not usable in inplace edit mode
  output = $-i ? STDOUT : STDERR
}
output = STDERR if ARGF.file == STDIN
END {
  output.print date.strftime("latest_date=%F") if date
}
if gem = $F[0]
  ver = Gem::Version.new($F[1])
  (gem, src), = Gem::SpecFetcher.fetcher.detect(:latest) {|s|
    s.platform == "ruby" && s.name == gem
  }
  if gem.version > ver
    gem = src.fetch_spec(gem)
    if ENV["UPDATE_BUNDLED_GEMS_ALL"]
      uri = gem.metadata["source_code_uri"] || gem.homepage
      uri = uri.sub(%r[\Ahttps://github\.com/[^/]+/[^/]+\K/tree/.*], "").chomp(".git")
    else
      uri = $F[2]
    end
    if (!date or gem.date && gem.date > date) and gem.date.to_i != 315_619_200
      # DEFAULT_SOURCE_DATE_EPOCH is meaningless
      date = gem.date
    end
    if $F[3]
      if $F[3].include?($F[1])
        $F[3][$F[1]] = gem.version.to_s
      elsif Gem::Version.new($F[1]) != gem.version and /\A\h+\z/ =~ $F[3]
        $F[3..-1] = []
      end
    end
    f = [gem.name, gem.version.to_s, uri, *$F[3..-1]]
    $_.gsub!(/\S+\s*(?=\s|$)/) {|s| (f.shift || "").ljust(s.size)}
    $_ = [$_, *f].join(" ") unless f.empty?
    $_.rstrip!
  end
end
