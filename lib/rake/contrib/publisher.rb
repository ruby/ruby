# Copyright 2003, 2004, 2005, 2006, 2007, 2008 by Jim Weirich (jim@weirichhouse.org)
# All rights reserved.

# Permission is granted for use, copying, modification, distribution,
# and distribution of modified versions of this work as long as the
# above copyright notice is included.

# Configuration information about an upload host system.
# * name   :: Name of host system.
# * webdir :: Base directory for the web information for the
#             application.  The application name (APP) is appended to
#             this directory before using.
# * pkgdir :: Directory on the host system where packages can be
#             placed.
HostInfo = Struct.new(:name, :webdir, :pkgdir)

# Manage several publishers as a single entity.
class CompositePublisher
  def initialize
    @publishers = []
  end

  # Add a publisher to the composite.
  def add(pub)
    @publishers << pub
  end

  # Upload all the individual publishers.
  def upload
    @publishers.each { |p| p.upload }
  end
end

# Publish an entire directory to an existing remote directory using
# SSH.
class SshDirPublisher
  def initialize(host, remote_dir, local_dir)
    @host = host
    @remote_dir = remote_dir
    @local_dir = local_dir
  end

  def upload
    run %{scp -rq #{@local_dir}/* #{@host}:#{@remote_dir}}
  end
end

# Publish an entire directory to a fresh remote directory using SSH.
class SshFreshDirPublisher < SshDirPublisher
  def upload
    run %{ssh #{@host} rm -rf #{@remote_dir}} rescue nil
    run %{ssh #{@host} mkdir #{@remote_dir}}
    super
  end
end

# Publish a list of files to an existing remote directory.
class SshFilePublisher
  # Create a publisher using the give host information.
  def initialize(host, remote_dir, local_dir, *files)
    @host = host
    @remote_dir = remote_dir
    @local_dir = local_dir
    @files = files
  end

  # Upload the local directory to the remote directory.
  def upload
    @files.each do |fn|
      run %{scp -q #{@local_dir}/#{fn} #{@host}:#{@remote_dir}}
    end
  end
end
