# coding: utf-8
# frozen_string_literal: true

require 'rubygems/package/tar_test_case'
require 'rubygems/simple_gem'

class TestGemPackage < Gem::Package::TarTestCase

  def setup
    super

    @spec = quick_gem 'a' do |s|
      s.description = 'π'
      s.files = %w[lib/code.rb]
    end

    util_build_gem @spec

    @gem = @spec.cache_file

    @destination = File.join @tempdir, 'extract'

    FileUtils.mkdir_p @destination
  end

  def test_class_new_old_format
    File.open 'old_format.gem', 'wb' do |io|
      io.write SIMPLE_GEM
    end

    package = Gem::Package.new 'old_format.gem'

    assert package.spec
  end

  def test_add_checksums
    gem_io = StringIO.new

    spec = Gem::Specification.new 'build', '1'
    spec.summary = 'build'
    spec.authors = 'build'
    spec.files = ['lib/code.rb']
    spec.date = Time.at 0
    spec.rubygems_version = Gem::Version.new '0'

    FileUtils.mkdir 'lib'

    File.open 'lib/code.rb', 'w' do |io|
      io.write '# lib/code.rb'
    end

    package = Gem::Package.new spec.file_name
    package.spec = spec
    package.build_time = 1 # 0 uses current time
    package.setup_signer

    Gem::Package::TarWriter.new gem_io do |gem|
      package.add_metadata gem
      package.add_contents gem
      package.add_checksums gem
    end

    gem_io.rewind

    reader = Gem::Package::TarReader.new gem_io

    checksums = nil
    tar       = nil

    reader.each_entry do |entry|
      case entry.full_name
      when 'checksums.yaml.gz' then
        Zlib::GzipReader.wrap entry do |io|
          checksums = io.read
        end
      when 'data.tar.gz' then
        tar = entry.read
      end
    end

    s = StringIO.new

    package.gzip_to s do |io|
      io.write spec.to_yaml
    end

    metadata_sha256 = Digest::SHA256.hexdigest s.string
    metadata_sha512 = Digest::SHA512.hexdigest s.string

    expected = {
      'SHA512' => {
        'metadata.gz' => metadata_sha512,
        'data.tar.gz' => Digest::SHA512.hexdigest(tar),
      }
    }

    if defined?(OpenSSL::Digest)
      expected['SHA256'] = {
        'metadata.gz' => metadata_sha256,
        'data.tar.gz' => Digest::SHA256.hexdigest(tar),
      }
    end

    assert_equal expected, YAML.load(checksums)
  end

  def test_build_time_source_date_epoch
    epoch = ENV["SOURCE_DATE_EPOCH"]
    ENV["SOURCE_DATE_EPOCH"] = "123456789"

    spec = Gem::Specification.new 'build', '1'
    spec.summary = 'build'
    spec.authors = 'build'
    spec.files = ['lib/code.rb']
    spec.date = Time.at 0
    spec.rubygems_version = Gem::Version.new '0'

    package = Gem::Package.new spec.file_name

    assert_equal Time.at(ENV["SOURCE_DATE_EPOCH"].to_i).utc, package.build_time
  ensure
    ENV["SOURCE_DATE_EPOCH"] = epoch
  end

  def test_add_files
    spec = Gem::Specification.new
    spec.files = %w[lib/code.rb lib/empty]

    FileUtils.mkdir_p 'lib/empty'

    File.open 'lib/code.rb',  'w' do |io|
      io.write '# lib/code.rb'
    end

    File.open 'lib/extra.rb', 'w' do |io|
      io.write '# lib/extra.rb'
    end

    package = Gem::Package.new 'bogus.gem'
    package.spec = spec

    tar = util_tar do |tar_io|
      package.add_files tar_io
    end

    tar.rewind

    files = []

    Gem::Package::TarReader.new tar do |tar_io|
      tar_io.each_entry do |entry|
        files << entry.full_name
      end
    end

    assert_equal %w[lib/code.rb], files
  end

  def test_add_files_symlink
    spec = Gem::Specification.new
    spec.files = %w[lib/code.rb lib/code_sym.rb lib/code_sym2.rb]

    FileUtils.mkdir_p 'lib'

    File.open 'lib/code.rb',  'w' do |io|
      io.write '# lib/code.rb'
    end

    # NOTE: 'code.rb' is correct, because it's relative to lib/code_sym.rb
    begin
      File.symlink('code.rb', 'lib/code_sym.rb')
      File.symlink('../lib/code.rb', 'lib/code_sym2.rb')
    rescue Errno::EACCES => e
      if win_platform?
        skip "symlink - must be admin with no UAC on Windows"
      else
        raise e
      end
    end

    package = Gem::Package.new 'bogus.gem'
    package.spec = spec

    tar = util_tar do |tar_io|
      package.add_files tar_io
    end

    tar.rewind

    files, symlinks = [], []

    Gem::Package::TarReader.new tar do |tar_io|
      tar_io.each_entry do |entry|
        if entry.symlink?
          symlinks << { entry.full_name => entry.header.linkname }
        else
          files << entry.full_name
        end
      end
    end

    assert_equal %w[lib/code.rb], files
    assert_equal [{'lib/code_sym.rb' => 'lib/code.rb'}, {'lib/code_sym2.rb' => '../lib/code.rb'}], symlinks
  end

  def test_build
    spec = Gem::Specification.new 'build', '1'
    spec.summary = 'build'
    spec.authors = 'build'
    spec.files = ['lib/code.rb']
    spec.rubygems_version = :junk

    FileUtils.mkdir 'lib'

    File.open 'lib/code.rb', 'w' do |io|
      io.write '# lib/code.rb'
    end

    package = Gem::Package.new spec.file_name
    package.spec = spec

    package.build

    assert_equal Gem::VERSION, spec.rubygems_version
    assert_path_exists spec.file_name

    reader = Gem::Package.new spec.file_name
    assert_equal spec, reader.spec

    assert_equal %w[metadata.gz data.tar.gz checksums.yaml.gz],
                 reader.files

    assert_equal %w[lib/code.rb], reader.contents
  end

  def test_build_auto_signed
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    FileUtils.mkdir_p File.join(Gem.user_home, '.gem')

    private_key_path = File.join Gem.user_home, '.gem', 'gem-private_key.pem'
    Gem::Security.write PRIVATE_KEY, private_key_path

    public_cert_path = File.join Gem.user_home, '.gem', 'gem-public_cert.pem'
    FileUtils.cp PUBLIC_CERT_PATH, public_cert_path

    spec = Gem::Specification.new 'build', '1'
    spec.summary = 'build'
    spec.authors = 'build'
    spec.files = ['lib/code.rb']

    FileUtils.mkdir 'lib'

    File.open 'lib/code.rb', 'w' do |io|
      io.write '# lib/code.rb'
    end

    package = Gem::Package.new spec.file_name
    package.spec = spec

    package.build

    assert_equal Gem::VERSION, spec.rubygems_version
    assert_path_exists spec.file_name

    reader = Gem::Package.new spec.file_name
    assert reader.verify

    assert_equal [PUBLIC_CERT.to_pem], reader.spec.cert_chain

    assert_equal %w[metadata.gz       metadata.gz.sig
                    data.tar.gz       data.tar.gz.sig
                    checksums.yaml.gz checksums.yaml.gz.sig],
                 reader.files

    assert_equal %w[lib/code.rb], reader.contents
  end

  def test_build_auto_signed_encrypted_key
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    FileUtils.mkdir_p File.join(Gem.user_home, '.gem')

    private_key_path = File.join Gem.user_home, '.gem', 'gem-private_key.pem'
    FileUtils.cp ENCRYPTED_PRIVATE_KEY_PATH, private_key_path

    public_cert_path = File.join Gem.user_home, '.gem', 'gem-public_cert.pem'
    Gem::Security.write PUBLIC_CERT, public_cert_path

    spec = Gem::Specification.new 'build', '1'
    spec.summary = 'build'
    spec.authors = 'build'
    spec.files = ['lib/code.rb']

    FileUtils.mkdir 'lib'

    File.open 'lib/code.rb', 'w' do |io|
      io.write '# lib/code.rb'
    end

    package = Gem::Package.new spec.file_name
    package.spec = spec

    package.build

    assert_equal Gem::VERSION, spec.rubygems_version
    assert_path_exists spec.file_name

    reader = Gem::Package.new spec.file_name
    assert reader.verify

    assert_equal [PUBLIC_CERT.to_pem], reader.spec.cert_chain

    assert_equal %w[metadata.gz       metadata.gz.sig
                    data.tar.gz       data.tar.gz.sig
                    checksums.yaml.gz checksums.yaml.gz.sig],
                 reader.files

    assert_equal %w[lib/code.rb], reader.contents
  end

  def test_build_invalid
    spec = Gem::Specification.new 'build', '1'

    package = Gem::Package.new spec.file_name
    package.spec = spec

    e = assert_raises Gem::InvalidSpecificationException do
      package.build
    end

    assert_equal 'missing value for attribute summary', e.message
  end

  def test_build_invalid_arguments
    spec = Gem::Specification.new 'build', '1'

    package = Gem::Package.new spec.file_name
    package.spec = spec

    e = assert_raises ArgumentError do
      package.build true, true
    end

    assert_equal "skip_validation = true and strict_validation = true are incompatible", e.message
  end

  def test_build_signed
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    spec = Gem::Specification.new 'build', '1'
    spec.summary = 'build'
    spec.authors = 'build'
    spec.files = ['lib/code.rb']
    spec.cert_chain = [PUBLIC_CERT.to_pem]
    spec.signing_key = PRIVATE_KEY

    FileUtils.mkdir 'lib'

    File.open 'lib/code.rb', 'w' do |io|
      io.write '# lib/code.rb'
    end

    package = Gem::Package.new spec.file_name
    package.spec = spec

    package.build

    assert_equal Gem::VERSION, spec.rubygems_version
    assert_path_exists spec.file_name

    reader = Gem::Package.new spec.file_name
    assert reader.verify

    assert_equal spec, reader.spec

    assert_equal %w[metadata.gz       metadata.gz.sig
                    data.tar.gz       data.tar.gz.sig
                    checksums.yaml.gz checksums.yaml.gz.sig],
                 reader.files

    assert_equal %w[lib/code.rb], reader.contents
  end

  def test_build_signed_encrypted_key
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    spec = Gem::Specification.new 'build', '1'
    spec.summary = 'build'
    spec.authors = 'build'
    spec.files = ['lib/code.rb']
    spec.cert_chain = [PUBLIC_CERT.to_pem]
    spec.signing_key = ENCRYPTED_PRIVATE_KEY

    FileUtils.mkdir 'lib'

    File.open 'lib/code.rb', 'w' do |io|
      io.write '# lib/code.rb'
    end

    package = Gem::Package.new spec.file_name
    package.spec = spec

    package.build

    assert_equal Gem::VERSION, spec.rubygems_version
    assert_path_exists spec.file_name

    reader = Gem::Package.new spec.file_name
    assert reader.verify

    assert_equal spec, reader.spec

    assert_equal %w[metadata.gz       metadata.gz.sig
                    data.tar.gz       data.tar.gz.sig
                    checksums.yaml.gz checksums.yaml.gz.sig],
                 reader.files

    assert_equal %w[lib/code.rb], reader.contents
  end

  def test_contents
    package = Gem::Package.new @gem

    assert_equal %w[lib/code.rb], package.contents
  end

  def test_extract_files
    package = Gem::Package.new @gem

    package.extract_files @destination

    extracted = File.join @destination, 'lib/code.rb'
    assert_path_exists extracted

    mask = 0100666 & (~File.umask)

    assert_equal mask.to_s(8), File.stat(extracted).mode.to_s(8) unless
      win_platform?
  end

  def test_extract_files_empty
    data_tgz = util_tar_gz { }

    gem = util_tar do |tar|
      tar.add_file 'data.tar.gz', 0644 do |io|
        io.write data_tgz.string
      end

      tar.add_file 'metadata.gz', 0644 do |io|
        Zlib::GzipWriter.wrap io do |gzio|
          gzio.write @spec.to_yaml
        end
      end
    end

    File.open 'empty.gem', 'wb' do |io|
      io.write gem.string
    end

    package = Gem::Package.new 'empty.gem'

    package.extract_files @destination

    assert_path_exists @destination
  end

  def test_extract_tar_gz_absolute
    package = Gem::Package.new @gem

    tgz_io = util_tar_gz do |tar|
      tar.add_file '/absolute.rb', 0644 do |io|
        io.write 'hi'
      end
    end

    e = assert_raises Gem::Package::PathError do
      package.extract_tar_gz tgz_io, @destination
    end

    assert_equal("installing into parent path /absolute.rb of " +
                 "#{@destination} is not allowed", e.message)
  end

  def test_extract_tar_gz_symlink_relative_path
    package = Gem::Package.new @gem

    tgz_io = util_tar_gz do |tar|
      tar.add_file    'relative.rb', 0644 do |io|
        io.write 'hi'
      end

      tar.mkdir       'lib',         0755
      tar.add_symlink 'lib/foo.rb', '../relative.rb', 0644
    end

    begin
      package.extract_tar_gz tgz_io, @destination
    rescue Errno::EACCES => e
      if win_platform?
        skip "symlink - must be admin with no UAC on Windows"
      else
        raise e
      end
    end

    extracted = File.join @destination, 'lib/foo.rb'
    assert_path_exists extracted
    assert_equal '../relative.rb',
                 File.readlink(extracted)
    assert_equal 'hi',
                 File.read(extracted)
  end

  def test_extract_symlink_parent
    package = Gem::Package.new @gem

    tgz_io = util_tar_gz do |tar|
      tar.mkdir       'lib',               0755
      tar.add_symlink 'lib/link', '../..', 0644
      tar.add_file    'lib/link/outside.txt', 0644 do |io|
        io.write 'hi'
      end
    end

    # Extract into a subdirectory of @destination; if this test fails it writes
    # a file outside destination_subdir, but we want the file to remain inside
    # @destination so it will be cleaned up.
    destination_subdir = File.join @destination, 'subdir'
    FileUtils.mkdir_p destination_subdir

    e = assert_raises(Gem::Package::PathError, Errno::EACCES) do
      package.extract_tar_gz tgz_io, destination_subdir
    end

    if Gem::Package::PathError === e
      assert_equal("installing into parent path lib/link/outside.txt of " +
                  "#{destination_subdir} is not allowed", e.message)
    elsif win_platform?
      skip "symlink - must be admin with no UAC on Windows"
    else
      raise e
    end
  end

  def test_extract_symlink_parent_doesnt_delete_user_dir
    package = Gem::Package.new @gem

    # Extract into a subdirectory of @destination; if this test fails it writes
    # a file outside destination_subdir, but we want the file to remain inside
    # @destination so it will be cleaned up.
    destination_subdir = File.join @destination, 'subdir'
    FileUtils.mkdir_p destination_subdir

    destination_user_dir = File.join @destination, 'user'
    destination_user_subdir = File.join destination_user_dir, 'dir'
    FileUtils.mkdir_p destination_user_subdir

    tgz_io = util_tar_gz do |tar|
      tar.add_symlink 'link', destination_user_dir, 16877
      tar.add_symlink 'link/dir', '.', 16877
    end

    e = assert_raises(Gem::Package::PathError, Errno::EACCES) do
      package.extract_tar_gz tgz_io, destination_subdir
    end

    assert_path_exists destination_user_subdir

    if Gem::Package::PathError === e
      assert_equal("installing into parent path #{destination_user_subdir} of " +
                  "#{destination_subdir} is not allowed", e.message)
    elsif win_platform?
      skip "symlink - must be admin with no UAC on Windows"
    else
      raise e
    end
  end

  def test_extract_tar_gz_directory
    package = Gem::Package.new @gem

    tgz_io = util_tar_gz do |tar|
      tar.mkdir    'lib',        0755
      tar.add_file 'lib/foo.rb', 0644 do |io|
        io.write 'hi'
      end
      tar.mkdir    'lib/foo',    0755
    end

    package.extract_tar_gz tgz_io, @destination

    extracted = File.join @destination, 'lib/foo.rb'
    assert_path_exists extracted

    extracted = File.join @destination, 'lib/foo'
    assert_path_exists extracted
  end

  def test_extract_tar_gz_dot_slash
    package = Gem::Package.new @gem

    tgz_io = util_tar_gz do |tar|
      tar.add_file './dot_slash.rb', 0644 do |io|
        io.write 'hi'
      end
    end

    package.extract_tar_gz tgz_io, @destination

    extracted = File.join @destination, 'dot_slash.rb'
    assert_path_exists extracted
  end

  def test_extract_tar_gz_dot_file
    package = Gem::Package.new @gem

    tgz_io = util_tar_gz do |tar|
      tar.add_file '.dot_file.rb', 0644 do |io|
        io.write 'hi'
      end
    end

    package.extract_tar_gz tgz_io, @destination

    extracted = File.join @destination, '.dot_file.rb'
    assert_path_exists extracted
  end

  if Gem.win_platform?
    def test_extract_tar_gz_case_insensitive
      package = Gem::Package.new @gem

      tgz_io = util_tar_gz do |tar|
        tar.add_file 'foo/file.rb', 0644 do |io|
          io.write 'hi'
        end
      end

      package.extract_tar_gz tgz_io, @destination.upcase

      extracted = File.join @destination, 'foo/file.rb'
      assert_path_exists extracted
    end
  end

  def test_install_location
    package = Gem::Package.new @gem

    file = 'file.rb'.dup
    file.taint

    destination = package.install_location file, @destination

    assert_equal File.join(@destination, 'file.rb'), destination
    refute destination.tainted?
  end

  def test_install_location_absolute
    package = Gem::Package.new @gem

    e = assert_raises Gem::Package::PathError do
      package.install_location '/absolute.rb', @destination
    end

    assert_equal("installing into parent path /absolute.rb of " +
                 "#{@destination} is not allowed", e.message)
  end

  def test_install_location_dots
    package = Gem::Package.new @gem

    file = 'file.rb'

    destination = File.join @destination, 'foo', '..', 'bar'

    FileUtils.mkdir_p File.join @destination, 'foo'
    FileUtils.mkdir_p File.expand_path destination

    destination = package.install_location file, destination

    # this test only fails on ruby missing File.realpath
    assert_equal File.join(@destination, 'bar', 'file.rb'), destination
  end

  def test_install_location_extra_slash
    package = Gem::Package.new @gem

    file = 'foo//file.rb'.dup
    file.taint

    destination = @destination.sub '/', '//'

    destination = package.install_location file, destination

    assert_equal File.join(@destination, 'foo', 'file.rb'), destination
    refute destination.tainted?
  end

  def test_install_location_relative
    package = Gem::Package.new @gem

    e = assert_raises Gem::Package::PathError do
      package.install_location '../relative.rb', @destination
    end

    parent = File.expand_path File.join @destination, "../relative.rb"

    assert_equal("installing into parent path #{parent} of " +
                 "#{@destination} is not allowed", e.message)
  end

  def test_install_location_suffix
    package = Gem::Package.new @gem

    filename = "../#{File.basename(@destination)}suffix.rb"

    e = assert_raises Gem::Package::PathError do
      package.install_location filename, @destination
    end

    parent = File.expand_path File.join @destination, filename

    assert_equal("installing into parent path #{parent} of " +
                 "#{@destination} is not allowed", e.message)
  end

  def test_load_spec
    entry = StringIO.new Gem::Util.gzip @spec.to_yaml
    def entry.full_name() 'metadata.gz' end

    package = Gem::Package.new 'nonexistent.gem'

    spec = package.load_spec entry

    assert_equal @spec, spec
  end

  def test_verify
    package = Gem::Package.new @gem

    package.verify

    assert_equal @spec, package.spec
    assert_equal %w[checksums.yaml.gz data.tar.gz metadata.gz],
                 package.files.sort
  end

  def test_verify_checksum_bad
    data_tgz = util_tar_gz do |tar|
      tar.add_file 'lib/code.rb', 0444 do |io|
        io.write '# lib/code.rb'
      end
    end

    data_tgz = data_tgz.string

    gem = util_tar do |tar|
      metadata_gz = Gem::Util.gzip @spec.to_yaml

      tar.add_file 'metadata.gz', 0444 do |io|
        io.write metadata_gz
      end

      tar.add_file 'data.tar.gz', 0444 do |io|
        io.write data_tgz
      end

      bogus_checksums = {
        'SHA1' => {
          'data.tar.gz' => 'bogus',
          'metadata.gz' => 'bogus',
        },
      }
      tar.add_file 'checksums.yaml.gz', 0444 do |io|
        Zlib::GzipWriter.wrap io do |gz_io|
          gz_io.write YAML.dump bogus_checksums
        end
      end
    end

    File.open 'mismatch.gem', 'wb' do |io|
      io.write gem.string
    end

    package = Gem::Package.new 'mismatch.gem'

    e = assert_raises Gem::Package::FormatError do
      package.verify
    end

    assert_equal 'SHA1 checksum mismatch for data.tar.gz in mismatch.gem',
                 e.message
  end

  def test_verify_checksum_missing
    data_tgz = util_tar_gz do |tar|
      tar.add_file 'lib/code.rb', 0444 do |io|
        io.write '# lib/code.rb'
      end
    end

    data_tgz = data_tgz.string

    gem = util_tar do |tar|
      metadata_gz = Gem::Util.gzip @spec.to_yaml

      tar.add_file 'metadata.gz', 0444 do |io|
        io.write metadata_gz
      end

      digest = Digest::SHA1.new
      digest << metadata_gz

      checksums = {
        'SHA1' => {
          'metadata.gz' => digest.hexdigest,
        },
      }

      tar.add_file 'checksums.yaml.gz', 0444 do |io|
        Zlib::GzipWriter.wrap io do |gz_io|
          gz_io.write YAML.dump checksums
        end
      end

      tar.add_file 'data.tar.gz', 0444 do |io|
        io.write data_tgz
      end
    end

    File.open 'data_checksum_missing.gem', 'wb' do |io|
      io.write gem.string
    end

    package = Gem::Package.new 'data_checksum_missing.gem'

    assert package.verify
  end

  def test_verify_corrupt
    tf = Tempfile.open 'corrupt' do |io|
      data = Gem::Util.gzip 'a' * 10
      io.write \
        tar_file_header('metadata.gz', "\000x", 0644, data.length, Time.now)
      io.write data
      io.rewind

      package = Gem::Package.new io.path

      e = assert_raises Gem::Package::FormatError do
        package.verify
      end

      assert_equal "tar is corrupt, name contains null byte in #{io.path}",
                   e.message
      io
    end
    tf.close!
  end

  def test_verify_empty
    FileUtils.touch 'empty.gem'

    package = Gem::Package.new 'empty.gem'

    e = assert_raises Gem::Package::FormatError do
      package.verify
    end

    assert_equal 'package metadata is missing in empty.gem', e.message
  end

  def test_verify_nonexistent
    package = Gem::Package.new 'nonexistent.gem'

    e = assert_raises Gem::Package::FormatError do
      package.verify
    end

    assert_match %r%^No such file or directory%, e.message
    assert_match %r%nonexistent.gem$%,           e.message
  end

  def test_verify_duplicate_file
    FileUtils.mkdir_p 'lib'
    FileUtils.touch 'lib/code.rb'

    build = Gem::Package.new @gem
    build.spec = @spec
    build.setup_signer
    open @gem, 'wb' do |gem_io|
      Gem::Package::TarWriter.new gem_io do |gem|
        build.add_metadata gem
        build.add_contents gem

        gem.add_file_simple 'a.sig', 0444, 0
        gem.add_file_simple 'a.sig', 0444, 0
      end
    end

    package = Gem::Package.new @gem

    e = assert_raises Gem::Security::Exception do
      package.verify
    end

    assert_equal 'duplicate files in the package: ("a.sig")', e.message
  end

  def test_verify_security_policy
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    package = Gem::Package.new @gem
    package.security_policy = Gem::Security::HighSecurity

    e = assert_raises Gem::Security::Exception do
      package.verify
    end

    assert_equal 'unsigned gems are not allowed by the High Security policy',
                 e.message

    refute package.instance_variable_get(:@spec), '@spec must not be loaded'
    assert_empty package.instance_variable_get(:@files), '@files must empty'
  end

  def test_verify_security_policy_low_security
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    @spec.cert_chain = [PUBLIC_CERT.to_pem]
    @spec.signing_key = PRIVATE_KEY

    FileUtils.mkdir_p 'lib'
    FileUtils.touch 'lib/code.rb'

    build = Gem::Package.new @gem
    build.spec = @spec

    build.build

    package = Gem::Package.new @gem
    package.security_policy = Gem::Security::LowSecurity

    assert package.verify
  end

  def test_verify_security_policy_checksum_missing
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    @spec.cert_chain = [PUBLIC_CERT.to_pem]
    @spec.signing_key = PRIVATE_KEY

    build = Gem::Package.new @gem
    build.spec = @spec
    build.setup_signer

    FileUtils.mkdir 'lib'
    FileUtils.touch 'lib/code.rb'

    File.open @gem, 'wb' do |gem_io|
      Gem::Package::TarWriter.new gem_io do |gem|
        build.add_metadata gem
        build.add_contents gem

        # write bogus data.tar.gz to foil signature
        bogus_data = Gem::Util.gzip 'hello'
        fake_signer = Class.new do
          def digest_name; 'SHA512'; end
          def digest_algorithm; Digest(:SHA512); end
          def key; 'key'; end
          def sign(*); 'fake_sig'; end
        end
        gem.add_file_signed 'data2.tar.gz', 0444, fake_signer.new do |io|
          io.write bogus_data
        end

        # pre rubygems 2.0 gems do not add checksums
      end
    end

    Gem::Security.trust_dir.trust_cert PUBLIC_CERT

    package = Gem::Package.new @gem
    package.security_policy = Gem::Security::HighSecurity

    e = assert_raises Gem::Security::Exception do
      package.verify
    end

    assert_equal 'invalid signature', e.message

    refute package.instance_variable_get(:@spec), '@spec must not be loaded'
    assert_empty package.instance_variable_get(:@files), '@files must empty'
  end

  def test_verify_truncate
    File.open 'bad.gem', 'wb' do |io|
      io.write File.read(@gem, 1024) # don't care about newlines
    end

    package = Gem::Package.new 'bad.gem'

    e = assert_raises Gem::Package::FormatError do
      package.verify
    end

    assert_equal 'package content (data.tar.gz) is missing in bad.gem',
                 e.message
  end

  # end #verify tests

  def test_verify_entry
    entry = Object.new
    def entry.full_name() raise ArgumentError, 'whatever' end

    package = Gem::Package.new @gem

    e = assert_raises Gem::Package::FormatError do
      package.verify_entry entry
    end

    assert_equal "package is corrupt, exception while verifying: whatever (ArgumentError) in #{@gem}", e.message

    valid_metadata = ["metadata", "metadata.gz"]
    valid_metadata.each do |vm|
      $spec_loaded = false
      $good_name = vm

      entry = Object.new
      def entry.full_name() $good_name end

      package = Gem::Package.new(@gem)
      package.instance_variable_set(:@files, [])
      def package.load_spec(entry) $spec_loaded = true end

      package.verify_entry(entry)

      assert $spec_loaded
    end

    invalid_metadata = ["metadataxgz", "foobar\nmetadata", "metadata\nfoobar"]
    invalid_metadata.each do |vm|
      $spec_loaded = false
      $bad_name = vm

      entry = Object.new
      def entry.full_name() $bad_name  end

      package = Gem::Package.new(@gem)
      package.instance_variable_set(:@files, [])
      def package.load_spec(entry) $spec_loaded = true end

      package.verify_entry(entry)

      refute $spec_loaded
    end
  end

  def test_spec
    package = Gem::Package.new @gem

    assert_equal @spec, package.spec
  end

  def test_spec_from_io
    # This functionality is used by rubygems.org to extract spec data from an
    # uploaded gem before it is written to storage.
    io = StringIO.new Gem.read_binary @gem
    package = Gem::Package.new io

    assert_equal @spec, package.spec
  end

  def test_spec_from_io_raises_gem_error_for_io_not_at_start
    io = StringIO.new Gem.read_binary @gem
    io.read(1)
    assert_raises(Gem::Package::Error) do
      Gem::Package.new io
    end
  end

  def util_tar
    tar_io = StringIO.new

    Gem::Package::TarWriter.new tar_io do |tar|
      yield tar
    end

    tar_io.rewind

    tar_io
  end

  def util_tar_gz(&block)
    tar_io = util_tar(&block)

    tgz_io = StringIO.new

    # can't wrap TarWriter because it seeks
    Zlib::GzipWriter.wrap tgz_io do |io|
      io.write tar_io.string
    end

    StringIO.new tgz_io.string
  end

end
