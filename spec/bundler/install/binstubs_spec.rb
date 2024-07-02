# frozen_string_literal: true

RSpec.describe "bundle install" do
  describe "when system_bindir is set" do
    it "overrides Gem.bindir" do
      expect(Pathname.new("/usr/bin")).not_to be_writable
      gemfile <<-G
        def Gem.bindir; "/usr/bin"; end
        source "https://gem.repo1"
        gem "myrack"
      G

      config "BUNDLE_SYSTEM_BINDIR" => system_gem_path("altbin").to_s
      bundle :install
      expect(the_bundle).to include_gems "myrack 1.0.0"
      expect(system_gem_path("altbin/myrackup")).to exist
    end
  end

  describe "when multiple gems contain the same exe" do
    before do
      build_repo2 do
        build_gem "fake", "14" do |s|
          s.executables = "myrackup"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo2"
        gem "fake"
        gem "myrack"
      G
    end

    it "warns about the situation" do
      bundle "exec myrackup"

      expect(last_command.stderr).to include(
        "The `myrackup` executable in the `fake` gem is being loaded, but it's also present in other gems (myrack).\n" \
        "If you meant to run the executable for another gem, make sure you use a project specific binstub (`bundle binstub <gem_name>`).\n" \
        "If you plan to use multiple conflicting executables, generate binstubs for them and disambiguate their names."
      ).or include(
        "The `myrackup` executable in the `myrack` gem is being loaded, but it's also present in other gems (fake).\n" \
        "If you meant to run the executable for another gem, make sure you use a project specific binstub (`bundle binstub <gem_name>`).\n" \
        "If you plan to use multiple conflicting executables, generate binstubs for them and disambiguate their names."
      )
    end
  end
end
