# TODO: Remove in Rake 11

require 'rake/contrib/sshpublisher'

module Rake

  class RubyForgePublisher < SshDirPublisher # :nodoc: all
    attr_reader :project, :proj_id, :user

    def initialize(projname, user)
      super(
        "#{user}@rubyforge.org",
        "/var/www/gforge-projects/#{projname}",
        "html")
    end
  end

end
