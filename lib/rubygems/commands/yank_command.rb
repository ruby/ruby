# frozen_string_literal: true
require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/version_option'
require 'rubygems/gemcutter_utilities'

class Gem::Commands::YankCommand < Gem::Command
  include Gem::LocalRemoteOptions
  include Gem::VersionOption
  include Gem::GemcutterUtilities

  def description # :nodoc:
    <<-EOF
The yank command removes a gem you pushed to a server from the server's
index.

Note that if you push a gem to rubygems.org the yank command does not
prevent other people from downloading the gem via the download link.

Once you have pushed a gem several downloads will happen automatically
via the webhooks.  If you accidentally pushed passwords or other sensitive
data you will need to change them immediately and yank your gem.

If you are yanking a gem due to intellectual property reasons contact
http://help.rubygems.org for permanent removal.  Be sure to mention this
as the reason for the removal request.
    EOF
  end

  def arguments # :nodoc:
    "GEM       name of gem"
  end

  def usage # :nodoc:
    "#{program_name} GEM -v VERSION [-p PLATFORM] [--key KEY_NAME] [--host HOST]"
  end

  def initialize
    super 'yank', 'Remove a pushed gem from the index'

    add_version_option("remove")
    add_platform_option("remove")

    add_option('--host HOST',
               'Yank from another gemcutter-compatible host') do |value, options|
      options[:host] = value
    end

    add_key_option
    @host = nil
  end

  def execute
    @host = options[:host]

    sign_in @host

    version   = get_version_from_requirements(options[:version])
    platform  = get_platform_from_requirements(options)

    if version then
      yank_gem(version, platform)
    else
      say "A version argument is required: #{usage}"
      terminate_interaction
    end
  end

  def yank_gem(version, platform)
    say "Yanking gem from #{self.host}..."
    yank_api_request(:delete, version, platform, "api/v1/gems/yank")
  end

  private

  def yank_api_request(method, version, platform, api)
    name = get_one_gem_name
    response = rubygems_api_request(method, api, host) do |request|
      request.add_field("Authorization", api_key)

      data = {
        'gem_name' => name,
        'version' => version,
      }
      data['platform'] = platform if platform

      request.set_form_data data
    end
    say response.body
  end

  def get_version_from_requirements(requirements)
    requirements.requirements.first[1].version
  rescue
    nil
  end

  def get_platform_from_requirements(requirements)
    Gem.platforms[1].to_s if requirements.key? :added_platform
  end

end

