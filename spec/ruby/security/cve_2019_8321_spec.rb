require_relative '../spec_helper'

guard_not -> { platform_is :darwin and ENV['GITHUB_ACTIONS'] } do # frequent timeout/hang on macOS in GitHub Actions
  require 'rubygems'
  require 'rubygems/user_interaction'

  describe "CVE-2019-8321 is resisted by" do
    it "sanitising verbose messages" do
      ui = Class.new {
        include Gem::UserInteraction
      }.new
      ui.should_receive(:say).with(".]2;nyan.")
      verbose_before = Gem.configuration.verbose
      begin
        Gem.configuration.verbose = :really_verbose
        ui.verbose("\e]2;nyan\a")
      ensure
        Gem.configuration.verbose = verbose_before
      end
    end
  end
end
