# frozen_string_literal: true

RSpec.describe "Requiring bundler" do
  it "takes care of requiring rubygems when entrypoint is bundler/setup" do
    sys_exec("#{Gem.ruby} -I#{lib_dir} -rbundler/setup -e'puts true'", env: { "RUBYOPT" => "--disable=gems" })

    expect(stdboth).to eq("true")
  end

  it "takes care of requiring rubygems when requiring just bundler" do
    sys_exec("#{Gem.ruby} -I#{lib_dir} -rbundler -e'puts true'", env: { "RUBYOPT" => "--disable=gems" })

    expect(stdboth).to eq("true")
  end

  it "shares RubyGems' own vendored URI with RubyGems" do
    ruby <<~R
      require "bundler/vendored_uri"
      require "rubygems/remote_fetcher"
      Gem::RemoteFetcher.fetcher
    R

    expect(err).to be_empty
  end
end
