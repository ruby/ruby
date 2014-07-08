require 'rake/dsl_definition'
require 'rake/contrib/compositepublisher'

module Rake

  # Publish an entire directory to an existing remote directory using
  # SSH.
  class SshDirPublisher
    include Rake::DSL

    # Creates an SSH publisher which will scp all files in +local_dir+ to
    # +remote_dir+ on +host+

    def initialize(host, remote_dir, local_dir)
      @host = host
      @remote_dir = remote_dir
      @local_dir = local_dir
    end

    # Uploads the files

    def upload
      sh "scp", "-rq", "#{@local_dir}/*", "#{@host}:#{@remote_dir}"
    end
  end

  # Publish an entire directory to a fresh remote directory using SSH.
  class SshFreshDirPublisher < SshDirPublisher

    # Uploads the files after removing the existing remote directory.

    def upload
      sh "ssh", @host, "rm", "-rf", @remote_dir rescue nil
      sh "ssh", @host, "mkdir",     @remote_dir
      super
    end
  end

  # Publish a list of files to an existing remote directory.
  class SshFilePublisher
    include Rake::DSL

    # Creates an SSH publisher which will scp all +files+ in +local_dir+ to
    # +remote_dir+ on +host+.

    def initialize(host, remote_dir, local_dir, *files)
      @host = host
      @remote_dir = remote_dir
      @local_dir = local_dir
      @files = files
    end

    # Uploads the files

    def upload
      @files.each do |fn|
        sh "scp", "-q", "#{@local_dir}/#{fn}", "#{@host}:#{@remote_dir}"
      end
    end
  end
end
