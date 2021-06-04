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
  $F[3][$F[1]] = gem.version.to_s if $F[3] && $F[3].include?($F[1])
  $_ = [gem.name, gem.version, uri, *$F[3..-1]].join(" ")
end
