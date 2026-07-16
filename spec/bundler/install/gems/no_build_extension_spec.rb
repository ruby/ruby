# frozen_string_literal: true

RSpec.describe "bundle install with --no-build-extension" do
  before do
    build_repo2 do
      build_gem "with_extension" do |s|
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("lib", __dir__)
            FileUtils.mkdir_p(path)
            File.open("\#{path}/with_extension.rb", "w") do |f|
              f.puts "WITH_EXTENSION = 'YES'"
            end
          end
        RUBY
      end
    end
  end

  it "skips building native extensions and warns when no_build_extension is set" do
    bundle_config "no_build_extension true"

    gemfile <<-G
      source "https://gem.repo2"
      gem "with_extension"
      gem "rake"
    G

    bundle :install

    build_complete = default_bundle_path("extensions").join(
      Gem::Platform.local.to_s,
      Gem.extension_api_version.to_s,
      "with_extension-1.0",
      "gem.build_complete"
    )
    expect(build_complete).not_to exist
    expect(err).to include("with_extension-1.0 contains native extensions that were not built")
    expect(err).to include("unset no_build_extension and run `bundle pristine with_extension`")
  end

  it "builds native extensions by default" do
    gemfile <<-G
      source "https://gem.repo2"
      gem "with_extension"
      gem "rake"
    G

    bundle :install

    expect(out).to include("Installing with_extension 1.0 with native extensions")
  end
end
