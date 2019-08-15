# frozen_string_literal: true
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

The gem can be removed from the index and deleted from the server using the yank
command.  For further discussion see the help for the yank command.

The push command will use ~/.gem/credentials to authenticate to a server, but you can use the RubyGems environment variable GEM_HOST_API_KEY to set the api key to authenticate.
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

    @user_defined_host = false

    add_proxy_option
    add_key_option
    add_otp_option

    add_option('--host HOST',
               'Push to another gemcutter-compatible host',
               '  (e.g. https://rubygems.org)') do |value, options|
      options[:host] = value
      @user_defined_host = true
    end

    @host = nil
  end

  def execute
    gem_name = get_one_gem_name
    default_gem_server, push_host = get_hosts_for(gem_name)

    default_host = nil
    user_defined_host = nil

    if @user_defined_host
      user_defined_host = options[:host]
    else
      default_host = options[:host]
    end

    @host = if user_defined_host
              user_defined_host
            elsif default_gem_server
              default_gem_server
            elsif push_host
              push_host
            else
              default_host
            end

    sign_in @host

    send_gem(gem_name)
  end

  def send_gem(name)
    args = [:post, "api/v1/gems"]

    latest_rubygems_version = Gem.latest_rubygems_version

    if latest_rubygems_version < Gem.rubygems_version and
         Gem.rubygems_version.prerelease? and
         Gem::Version.new('2.0.0.rc.2') != Gem.rubygems_version
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

    unless @host
      @host = gem_data.spec.metadata['default_gem_server']
    end

    push_host = nil

    if gem_data.spec.metadata.has_key?('allowed_push_host')
      push_host = gem_data.spec.metadata['allowed_push_host']
    end

    @host ||= push_host

    # Always include @host, even if it's nil
    args += [ @host, push_host ]

    say "Pushing gem to #{@host || Gem.host}..."

    response = send_push_request(name, args)

    with_response response
  end

  private

  def send_push_request(name, args)
    rubygems_api_request(*args) do |request|
      request.body = Gem.read_binary name
      request.add_field "Content-Length", request.body.size
      request.add_field "Content-Type",   "application/octet-stream"
      request.add_field "Authorization",  api_key
      request.add_field "OTP", options[:otp] if options[:otp]
    end
  end

  def get_hosts_for(name)
    gem_metadata = Gem::Package.new(name).spec.metadata

    [
      gem_metadata["default_gem_server"],
      gem_metadata["allowed_push_host"]
    ]
  end

end
