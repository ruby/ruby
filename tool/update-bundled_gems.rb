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
  uri = uri.sub(%r[\Ahttps://github\.com/[^/]+/[^/]+\K/tree/.*], "")
  $_ = [gem.name, gem.version, uri].join(" ")
end
