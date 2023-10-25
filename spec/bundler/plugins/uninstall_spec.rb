# frozen_string_literal: true

RSpec.describe "bundler plugin uninstall" do
  before do
    build_repo2 do
      build_plugin "foo"
      build_plugin "kung-foo"
    end
  end

  it "shows proper error message when plugins are not specified" do
    bundle "plugin uninstall"
    expect(err).to include("No plugins to uninstall")
  end

  it "uninstalls specified plugins" do
    bundle "plugin install foo kung-foo --source #{file_uri_for(gem_repo2)}"
    plugin_should_be_installed("foo")
    plugin_should_be_installed("kung-foo")

    bundle "plugin uninstall foo"
    expect(out).to include("Uninstalled plugin foo")
    plugin_should_not_be_installed("foo")
    plugin_should_be_installed("kung-foo")
  end

  it "shows proper message when plugin is not installed" do
    bundle "plugin uninstall foo"
    expect(err).to include("Plugin foo is not installed")
    plugin_should_not_be_installed("foo")
  end

  describe "with --all" do
    it "uninstalls all installed plugins" do
      bundle "plugin install foo kung-foo --source #{file_uri_for(gem_repo2)}"
      plugin_should_be_installed("foo")
      plugin_should_be_installed("kung-foo")

      bundle "plugin uninstall --all"
      plugin_should_not_be_installed("foo")
      plugin_should_not_be_installed("kung-foo")
    end

    it "shows proper no plugins installed message when no plugins installed" do
      bundle "plugin uninstall --all"
      expect(out).to include("No plugins installed")
    end
  end
end
