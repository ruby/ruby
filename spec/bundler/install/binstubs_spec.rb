# frozen_string_literal: true

RSpec.describe "bundle install" do
  describe "when system_bindir is set" do
    # On OS X, Gem.bindir defaults to /usr/bin, so system_bindir is useful if
    # you want to avoid sudo installs for system gems with OS X's default ruby
    it "overrides Gem.bindir" do
      expect(Pathname.new("/usr/bin")).not_to be_writable unless Process.euid == 0
      gemfile <<-G
        require 'rubygems'
        def Gem.bindir; "/usr/bin"; end
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      config "BUNDLE_SYSTEM_BINDIR" => system_gem_path("altbin").to_s
      bundle :install
      expect(the_bundle).to include_gems "rack 1.0.0"
      expect(system_gem_path("altbin/rackup")).to exist
    end
  end

  describe "when multiple gems contain the same exe" do
    before do
      build_repo2 do
        build_gem "fake", "14" do |s|
          s.executables = "rackup"
        end
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "fake"
        gem "rack"
      G
    end

    it "warns about the situation" do
      bundle! "exec rackup"

      expect(last_command.stderr).to include(
        "The `rackup` executable in the `fake` gem is being loaded, but it's also present in other gems (rack).\n" \
        "If you meant to run the executable for another gem, make sure you use a project specific binstub (`bundle binstub <gem_name>`).\n" \
        "If you plan to use multiple conflicting executables, generate binstubs for them and disambiguate their names."
      ).or include(
        "The `rackup` executable in the `rack` gem is being loaded, but it's also present in other gems (fake).\n" \
        "If you meant to run the executable for another gem, make sure you use a project specific binstub (`bundle binstub <gem_name>`).\n" \
        "If you plan to use multiple conflicting executables, generate binstubs for them and disambiguate their names."
      )
    end
  end
end
