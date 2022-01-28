require_relative '../spec_helper'

guard_not -> { platform_is :darwin and ENV['GITHUB_ACTIONS'] } do # frequent timeout/hang on macOS in GitHub Actions
  require 'yaml'
  require 'rubygems'
  require 'rubygems/safe_yaml'
  require 'rubygems/commands/owner_command'

  describe "CVE-2019-8322 is resisted by" do
    it "sanitising owner names" do
      command = Gem::Commands::OwnerCommand.new
      def command.rubygems_api_request(*args)
        Struct.new(:body).new("---\n- email: \"\e]2;nyan\a\"\n  handle: handle\n  id: id\n")
      end
      def command.with_response(response)
        yield response
      end
      command.should_receive(:say).with("Owners for gem: name")
      command.should_receive(:say).with("- .]2;nyan.")
      command.show_owners "name"
    end
  end
end
