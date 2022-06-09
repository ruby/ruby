#!ruby -pla
BEGIN {
  require 'rubygems'
}
unless /^[^#]/ !~ (gem = $F[0])
  (gem, src), = Gem::SpecFetcher.fetcher.detect(:latest) {|s|
    s.platform == "ruby" && s.name == gem
  }
  gem = src.fetch_spec(gem)
  uri = gem.metadata["source_code_uri"] || gem.homepage
  uri = uri.sub(%r[\Ahttps://github\.com/[^/]+/[^/]+\K/tree/.*], "").chomp(".git")
  if $F[3]
    if $F[3].include?($F[1])
      $F[3][$F[1]] = gem.version.to_s
    elsif Gem::Version.new($F[1]) != gem.version and /\A\h+\z/ =~ $F[3]
      $F[3..-1] = []
    end
  end
  $_ = [gem.name, gem.version, uri, *$F[3..-1]].join(" ")
end
