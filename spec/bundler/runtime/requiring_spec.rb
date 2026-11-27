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

  # See lib/rubygems/yaml_serializer/core.rb.
  %w[rubygems/vendor/uri/lib/uri rubygems/yaml_serializer].each do |feature|
    it "does not activate the installed Bundler gem when requiring #{feature}" do
      ruby <<~R
        begin
          require "#{feature}"
        rescue LoadError
        end
        print Gem.loaded_specs["bundler"]&.full_name.inspect
      R

      expect(out).to eq("nil")
    end
  end
end
