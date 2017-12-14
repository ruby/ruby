require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/gemcutter_utilities'
require 'rubygems/package'

class Gem::Commands::PushCommand < Gem::Command
  include Gem::LocalRemoteOptions
  include Gem::GemcutterUtilities

  def description # :nodoc:
    <<-EOF
The push command uploads a gem to the push server (the default is
https://rubygems.org) and adds it to the index.

The gem can be removed from the index (but only the index) using the yank
command.  For further discussion see the help for the yank command.
    EOF
  end

  def arguments # :nodoc:
    "GEM       built gem to push up"
  end

  def usage # :nodoc:
    "#{program_name} GEM"
  end

  def initialize
    super 'push', 'Push a gem up to the gem server', :host => self.host

    add_proxy_option
    add_key_option

    add_option('--host HOST',
               'Push to another gemcutter-compatible host') do |value, options|
      options[:host] = value
    end

    @host = nil
  end

  def execute
    @host = options[:host]

    sign_in @host

    send_gem get_one_gem_name
  end

  def send_gem name
    args = [:post, "api/v1/gems"]

    latest_rubygems_version = Gem.latest_rubygems_version

    if latest_rubygems_version < Gem.rubygems_version and
         Gem.rubygems_version.prerelease? and
         Gem::Version.new('2.0.0.rc.2') != Gem.rubygems_version then
      alert_error <<-ERROR
You are using a beta release of RubyGems (#{Gem::VERSION}) which is not
allowed to push gems.  Please downgrade or upgrade to a release version.

The latest released RubyGems version is #{latest_rubygems_version}

You can upgrade or downgrade to the latest release version with:

  gem update --system=#{latest_rubygems_version}

      ERROR
      terminate_interaction 1
    end

    gem_data = Gem::Package.new(name)

    unless @host then
      @host = gem_data.spec.metadata['default_gem_server']
    end

    # Always include this, even if it's nil
    args << @host

    if gem_data.spec.metadata.has_key?('allowed_push_host')
      args << gem_data.spec.metadata['allowed_push_host']
    end

    say "Pushing gem to #{@host || Gem.host}..."

    response = rubygems_api_request(*args) do |request|
      request.body = Gem.read_binary name
      request.add_field "Content-Length", request.body.size
      request.add_field "Content-Type",   "application/octet-stream"
      request.add_field "Authorization",  api_key
    end

    with_response response
  end

end

