# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/cert_command'

unless defined?(OpenSSL::SSL)
  warn 'Skipping `gem cert` tests.  openssl not found.'
end

if Gem.java_platform?
  warn 'Skipping `gem cert` tests on jruby.'
end

class TestGemCommandsCertCommand < Gem::TestCase

  ALTERNATE_CERT = load_cert 'alternate'
  EXPIRED_PUBLIC_CERT = load_cert 'expired'

  ALTERNATE_KEY_FILE = key_path 'alternate'
  PRIVATE_KEY_FILE   = key_path 'private'
  PUBLIC_KEY_FILE    = key_path 'public'

  ALTERNATE_CERT_FILE      = cert_path 'alternate'
  CHILD_CERT_FILE          = cert_path 'child'
  PUBLIC_CERT_FILE         = cert_path 'public'
  EXPIRED_PUBLIC_CERT_FILE = cert_path 'expired'

  def setup
    super

    @cmd = Gem::Commands::CertCommand.new

    @trust_dir = Gem::Security.trust_dir

    @cleanup = []
  end

  def teardown
    FileUtils.rm_f(@cleanup)

    super
  end

  def test_certificates_matching
    @trust_dir.trust_cert PUBLIC_CERT
    @trust_dir.trust_cert ALTERNATE_CERT

    matches = @cmd.certificates_matching ''

    # HACK OpenSSL::X509::Certificate#== is Object#==, so do this the hard way
    match = matches.next
    assert_equal ALTERNATE_CERT.to_pem, match.first.to_pem
    assert_equal @trust_dir.cert_path(ALTERNATE_CERT), match.last

    match = matches.next
    assert_equal PUBLIC_CERT.to_pem, match.first.to_pem
    assert_equal @trust_dir.cert_path(PUBLIC_CERT), match.last

    assert_raises StopIteration do
      matches.next
    end
  end

  def test_certificates_matching_filter
    @trust_dir.trust_cert PUBLIC_CERT
    @trust_dir.trust_cert ALTERNATE_CERT

    matches = @cmd.certificates_matching 'alternate'

    match = matches.next
    assert_equal ALTERNATE_CERT.to_pem, match.first.to_pem
    assert_equal @trust_dir.cert_path(ALTERNATE_CERT), match.last

    assert_raises StopIteration do
      matches.next
    end
  end

  def test_execute_add
    @cmd.handle_options %W[--add #{PUBLIC_CERT_FILE}]

    use_ui @ui do
      @cmd.execute
    end

    cert_path = @trust_dir.cert_path PUBLIC_CERT

    assert_path_exists cert_path

    assert_equal "Added '/CN=nobody/DC=example'\n", @ui.output
    assert_empty @ui.error
  end

  def test_execute_add_twice
    self.class.cert_path 'alternate'

    @cmd.handle_options %W[
      --add #{PUBLIC_CERT_FILE}
      --add #{ALTERNATE_CERT_FILE}
    ]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EXPECTED
Added '/CN=nobody/DC=example'
Added '/CN=alternate/DC=example'
    EXPECTED

    assert_equal expected, @ui.output
    assert_empty @ui.error
  end

  def test_execute_build
    passphrase = 'Foo bar'

    @cmd.handle_options %W[--build nobody@example.com]

    @build_ui = Gem::MockGemUi.new "#{passphrase}\n#{passphrase}"

    use_ui @build_ui do
      @cmd.execute
    end

    output = @build_ui.output.squeeze("\n").split "\n"

    assert_equal "Passphrase for your Private Key:  ",
                 output.shift
    assert_equal "Please repeat the passphrase for your Private Key:  ",
                 output.shift
    assert_equal "Certificate: #{File.join @tempdir, 'gem-public_cert.pem'}",
                 output.shift
    assert_equal "Private Key: #{File.join @tempdir, 'gem-private_key.pem'}",
                 output.shift

    assert_equal "Don't forget to move the key file to somewhere private!",
                 output.shift

    assert_empty output
    assert_empty @build_ui.error

    assert_path_exists File.join(@tempdir, 'gem-private_key.pem')
    assert_path_exists File.join(@tempdir, 'gem-public_cert.pem')
  end

  def test_execute_build_bad_email_address
    passphrase = 'Foo bar'
    email = "nobody@"

    @cmd.handle_options %W[--build #{email}]

    @build_ui = Gem::MockGemUi.new "#{passphrase}\n#{passphrase}"

    use_ui @build_ui do

      e = assert_raises Gem::CommandLineError do
        @cmd.execute
      end

      assert_equal "Invalid email address #{email}",
        e.message

      refute_path_exists File.join(@tempdir, 'gem-private_key.pem')
      refute_path_exists File.join(@tempdir, 'gem-public_cert.pem')
    end
  end

  def test_execute_build_expiration_days
    passphrase = 'Foo bar'

    @cmd.handle_options %W[
      --build nobody@example.com
      --days 26
    ]

    @build_ui = Gem::MockGemUi.new "#{passphrase}\n#{passphrase}"

    use_ui @build_ui do
      @cmd.execute
    end

    output = @build_ui.output.squeeze("\n").split "\n"

    assert_equal "Passphrase for your Private Key:  ",
                 output.shift
    assert_equal "Please repeat the passphrase for your Private Key:  ",
                 output.shift
    assert_equal "Certificate: #{File.join @tempdir, 'gem-public_cert.pem'}",
                 output.shift
    assert_equal "Private Key: #{File.join @tempdir, 'gem-private_key.pem'}",
                 output.shift

    assert_equal "Don't forget to move the key file to somewhere private!",
                 output.shift

    assert_empty output
    assert_empty @build_ui.error

    assert_path_exists File.join(@tempdir, 'gem-private_key.pem')
    assert_path_exists File.join(@tempdir, 'gem-public_cert.pem')

    pem = File.read("#{@tempdir}/gem-public_cert.pem")
    cert = OpenSSL::X509::Certificate.new(pem)

    test = (cert.not_after - cert.not_before).to_i / (24 * 60 * 60)
    assert_equal(test, 26)
  end

  def test_execute_build_bad_passphrase_confirmation
    passphrase = 'Foo bar'
    passphrase_confirmation = 'Fu bar'

    @cmd.handle_options %W[--build nobody@example.com]

    @build_ui = Gem::MockGemUi.new "#{passphrase}\n#{passphrase_confirmation}"

    use_ui @build_ui do
      e = assert_raises Gem::CommandLineError do
        @cmd.execute
      end

      output = @build_ui.output.squeeze("\n").split "\n"

      assert_equal "Passphrase for your Private Key:  ",
                   output.shift
      assert_equal "Please repeat the passphrase for your Private Key:  ",
                   output.shift

      assert_empty output

      assert_equal "Passphrase and passphrase confirmation don't match",
                   e.message

    end

    refute_path_exists File.join(@tempdir, 'gem-private_key.pem')
    refute_path_exists File.join(@tempdir, 'gem-public_cert.pem')
  end

  def test_execute_build_key
    @cmd.handle_options %W[
      --build nobody@example.com
      --private-key #{PRIVATE_KEY_FILE}
    ]

    use_ui @ui do
      @cmd.execute
    end

    output = @ui.output.split "\n"

    assert_equal "Certificate: #{File.join @tempdir, 'gem-public_cert.pem'}",
                 output.shift

    assert_empty output
    assert_empty @ui.error

    assert_path_exists File.join(@tempdir, 'gem-public_cert.pem')
    refute_path_exists File.join(@tempdir, 'gem-private_key.pem')
  end

  def test_execute_build_encrypted_key
    @cmd.handle_options %W[
      --build nobody@example.com
      --private-key #{ENCRYPTED_PRIVATE_KEY_PATH}
    ]

    use_ui @ui do
      @cmd.execute
    end

    output = @ui.output.split "\n"

    assert_equal "Certificate: #{File.join @tempdir, 'gem-public_cert.pem'}",
                 output.shift

    assert_empty output
    assert_empty @ui.error

    assert_path_exists File.join(@tempdir, 'gem-public_cert.pem')
  end

  def test_execute_certificate
    use_ui @ui do
      @cmd.handle_options %W[--certificate #{PUBLIC_CERT_FILE}]
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    assert_equal PUBLIC_CERT.to_pem, @cmd.options[:issuer_cert].to_pem
  end

  def test_execute_list
    @trust_dir.trust_cert PUBLIC_CERT
    @trust_dir.trust_cert ALTERNATE_CERT

    @cmd.handle_options %W[--list]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "/CN=alternate/DC=example\n/CN=nobody/DC=example\n",
                 @ui.output
    assert_empty @ui.error
  end

  def test_execute_list_filter
    @trust_dir.trust_cert PUBLIC_CERT
    @trust_dir.trust_cert ALTERNATE_CERT

    @cmd.handle_options %W[--list nobody]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "/CN=nobody/DC=example\n", @ui.output
    assert_empty @ui.error
  end

  def test_execute_private_key
    use_ui @ui do
      @cmd.send :handle_options, %W[--private-key #{PRIVATE_KEY_FILE}]
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    assert_equal PRIVATE_KEY.to_pem, @cmd.options[:key].to_pem
  end

  def test_execute_encrypted_private_key
    use_ui @ui do
      @cmd.send :handle_options, %W[--private-key #{ENCRYPTED_PRIVATE_KEY_PATH}]
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    assert_equal ENCRYPTED_PRIVATE_KEY.to_pem, @cmd.options[:key].to_pem
  end

  def test_execute_remove
    @trust_dir.trust_cert PUBLIC_CERT

    cert_path = @trust_dir.cert_path PUBLIC_CERT

    assert_path_exists cert_path

    @cmd.handle_options %W[--remove nobody]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "Removed '/CN=nobody/DC=example'\n", @ui.output
    assert_equal '', @ui.error

    refute_path_exists cert_path
  end

  def test_execute_remove_multiple
    @trust_dir.trust_cert PUBLIC_CERT
    @trust_dir.trust_cert ALTERNATE_CERT

    public_path = @trust_dir.cert_path PUBLIC_CERT
    alternate_path = @trust_dir.cert_path ALTERNATE_CERT

    assert_path_exists public_path
    assert_path_exists alternate_path

    @cmd.handle_options %W[--remove example]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EXPECTED
Removed '/CN=alternate/DC=example'
Removed '/CN=nobody/DC=example'
    EXPECTED

    assert_equal expected, @ui.output
    assert_equal '', @ui.error

    refute_path_exists public_path
    refute_path_exists alternate_path
  end

  def test_execute_remove_twice
    @trust_dir.trust_cert PUBLIC_CERT
    @trust_dir.trust_cert ALTERNATE_CERT

    public_path = @trust_dir.cert_path PUBLIC_CERT
    alternate_path = @trust_dir.cert_path ALTERNATE_CERT

    assert_path_exists public_path
    assert_path_exists alternate_path

    @cmd.handle_options %W[--remove nobody --remove alternate]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EXPECTED
Removed '/CN=nobody/DC=example'
Removed '/CN=alternate/DC=example'
    EXPECTED

    assert_equal expected, @ui.output
    assert_equal '', @ui.error

    refute_path_exists public_path
    refute_path_exists alternate_path
  end

  def test_execute_sign
    path = File.join @tempdir, 'cert.pem'
    Gem::Security.write ALTERNATE_CERT, path, 0600

    assert_equal '/CN=alternate/DC=example', ALTERNATE_CERT.issuer.to_s

    @cmd.handle_options %W[
      --private-key #{PRIVATE_KEY_FILE}
      --certificate #{PUBLIC_CERT_FILE}

      --sign #{path}
    ]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    cert = OpenSSL::X509::Certificate.new File.read path

    assert_equal '/CN=nobody/DC=example', cert.issuer.to_s

    mask = 0100600 & (~File.umask)

    assert_equal mask, File.stat(path).mode unless win_platform?
  end

  def test_execute_sign_encrypted_key
    path = File.join @tempdir, 'cert.pem'
    Gem::Security.write ALTERNATE_CERT, path, 0600

    assert_equal '/CN=alternate/DC=example', ALTERNATE_CERT.issuer.to_s

    @cmd.handle_options %W[
      --private-key #{ENCRYPTED_PRIVATE_KEY_PATH}
      --certificate #{PUBLIC_CERT_FILE}

      --sign #{path}
    ]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    cert = OpenSSL::X509::Certificate.new File.read path

    assert_equal '/CN=nobody/DC=example', cert.issuer.to_s

    mask = 0100600 & (~File.umask)

    assert_equal mask, File.stat(path).mode unless win_platform?
  end

  def test_execute_sign_default
    FileUtils.mkdir_p File.join Gem.user_home, '.gem'

    private_key_path = File.join Gem.user_home, '.gem', 'gem-private_key.pem'
    Gem::Security.write PRIVATE_KEY, private_key_path

    public_cert_path = File.join Gem.user_home, '.gem', 'gem-public_cert.pem'
    Gem::Security.write PUBLIC_CERT, public_cert_path

    path = File.join @tempdir, 'cert.pem'
    Gem::Security.write ALTERNATE_CERT, path, 0600

    assert_equal '/CN=alternate/DC=example', ALTERNATE_CERT.issuer.to_s

    @cmd.handle_options %W[--sign #{path}]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    cert = OpenSSL::X509::Certificate.new File.read path

    assert_equal '/CN=nobody/DC=example', cert.issuer.to_s

    mask = 0100600 & (~File.umask)

    assert_equal mask, File.stat(path).mode unless win_platform?
  end

  def test_execute_sign_default_encrypted_key
    FileUtils.mkdir_p File.join(Gem.user_home, '.gem')

    private_key_path = File.join Gem.user_home, '.gem', 'gem-private_key.pem'
    Gem::Security.write ENCRYPTED_PRIVATE_KEY, private_key_path, 0600, PRIVATE_KEY_PASSPHRASE

    public_cert_path = File.join Gem.user_home, '.gem', 'gem-public_cert.pem'
    Gem::Security.write PUBLIC_CERT, public_cert_path

    path = File.join @tempdir, 'cert.pem'
    Gem::Security.write ALTERNATE_CERT, path, 0600

    assert_equal '/CN=alternate/DC=example', ALTERNATE_CERT.issuer.to_s

    @cmd.handle_options %W[--sign #{path}]

    use_ui @ui do
      @cmd.execute
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    cert = OpenSSL::X509::Certificate.new File.read path

    assert_equal '/CN=nobody/DC=example', cert.issuer.to_s

    mask = 0100600 & (~File.umask)

    assert_equal mask, File.stat(path).mode unless win_platform?
  end

  def test_execute_sign_no_cert
    FileUtils.mkdir_p File.join Gem.user_home, '.gem'

    private_key_path = File.join Gem.user_home, '.gem', 'gem-private_key.pem'
    Gem::Security.write PRIVATE_KEY, private_key_path

    path = File.join @tempdir, 'cert.pem'
    Gem::Security.write ALTERNATE_CERT, path, 0600

    assert_equal '/CN=alternate/DC=example', ALTERNATE_CERT.issuer.to_s

    @cmd.handle_options %W[--sign #{path}]

    use_ui @ui do
      assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output

    expected = <<-EXPECTED
ERROR:  --certificate not specified and ~/.gem/gem-public_cert.pem does not exist
    EXPECTED

    assert_equal expected, @ui.error
  end

  def test_execute_sign_no_key
    FileUtils.mkdir_p File.join Gem.user_home, '.gem'

    public_cert_path = File.join Gem.user_home, '.gem', 'gem-public_cert.pem'
    Gem::Security.write PUBLIC_CERT, public_cert_path

    path = File.join @tempdir, 'cert.pem'
    Gem::Security.write ALTERNATE_CERT, path, 0600

    assert_equal '/CN=alternate/DC=example', ALTERNATE_CERT.issuer.to_s

    @cmd.handle_options %W[--sign #{path}]

    use_ui @ui do
      assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output

    expected = <<-EXPECTED
ERROR:  --private-key not specified and ~/.gem/gem-private_key.pem does not exist
    EXPECTED

    assert_equal expected, @ui.error
  end

  def test_execute_re_sign
    gem_path = File.join Gem.user_home, ".gem"
    Dir.mkdir gem_path

    path = File.join @tempdir, 'cert.pem'
    Gem::Security.write EXPIRED_PUBLIC_CERT, path, 0600

    assert_equal '/CN=nobody/DC=example', EXPIRED_PUBLIC_CERT.issuer.to_s

    tmp_expired_cert_file = File.join(Dir.tmpdir, File.basename(EXPIRED_PUBLIC_CERT_FILE))
    @cleanup << tmp_expired_cert_file
    File.write(tmp_expired_cert_file, File.read(EXPIRED_PUBLIC_CERT_FILE))

    @cmd.handle_options %W[
      --private-key #{PRIVATE_KEY_FILE}
      --certificate #{tmp_expired_cert_file}
      --re-sign
    ]

    use_ui @ui do
      @cmd.execute
    end

    expected_path = File.join(gem_path, "#{File.basename(tmp_expired_cert_file)}.expired")

    assert_match(
      /INFO:  Your certificate #{tmp_expired_cert_file} has been re-signed\nINFO:  Your expired certificate will be located at: #{expected_path}\.[0-9]+/,
      @ui.output
    )
    assert_equal '', @ui.error
  end

  def test_execute_re_sign_with_cert_expiration_length_days
    gem_path = File.join Gem.user_home, ".gem"
    Dir.mkdir gem_path

    path = File.join @tempdir, 'cert.pem'
    Gem::Security.write EXPIRED_PUBLIC_CERT, path, 0600

    assert_equal '/CN=nobody/DC=example', EXPIRED_PUBLIC_CERT.issuer.to_s

    tmp_expired_cert_file = File.join(Dir.tmpdir, File.basename(EXPIRED_PUBLIC_CERT_FILE))
    @cleanup << tmp_expired_cert_file
    File.write(tmp_expired_cert_file, File.read(EXPIRED_PUBLIC_CERT_FILE))

    @cmd.handle_options %W[
      --private-key #{PRIVATE_KEY_FILE}
      --certificate #{tmp_expired_cert_file}
      --re-sign
    ]

    Gem.configuration.cert_expiration_length_days = 28

    use_ui @ui do
      @cmd.execute
    end

    re_signed_cert = OpenSSL::X509::Certificate.new(File.read(tmp_expired_cert_file))
    cert_days_to_expire = (re_signed_cert.not_after - re_signed_cert.not_before).to_i / (24 * 60 * 60)

    assert_equal(28, cert_days_to_expire)
    assert_equal '', @ui.error
  end

  def test_handle_options
    @cmd.handle_options %W[
      --add #{PUBLIC_CERT_FILE}
      --add #{ALTERNATE_CERT_FILE}

      --remove nobody
      --remove example

      --list
      --list example

      --build nobody@example
      --build other@example
    ]

    assert_equal [PUBLIC_CERT.to_pem, ALTERNATE_CERT.to_pem],
                 @cmd.options[:add].map {|cert| cert.to_pem }

    assert_equal %w[nobody example], @cmd.options[:remove]

    assert_equal %w[nobody@example other@example],
                 @cmd.options[:build].map {|name| name.to_s }

    assert_equal ['', 'example'], @cmd.options[:list]
  end

  def test_handle_options_add_bad
    nonexistent = File.join @tempdir, 'nonexistent'
    e = assert_raises OptionParser::InvalidArgument do
      @cmd.handle_options %W[--add #{nonexistent}]
    end

    assert_equal "invalid argument: --add #{nonexistent}: does not exist",
                 e.message

    bad = File.join @tempdir, 'bad'
    FileUtils.touch bad

    e = assert_raises OptionParser::InvalidArgument do
      @cmd.handle_options %W[--add #{bad}]
    end

    assert_equal "invalid argument: --add #{bad}: invalid X509 certificate",
                 e.message
  end

  def test_handle_options_certificate
    nonexistent = File.join @tempdir, 'nonexistent'
    e = assert_raises OptionParser::InvalidArgument do
      @cmd.handle_options %W[--certificate #{nonexistent}]
    end

    assert_equal "invalid argument: --certificate #{nonexistent}: does not exist",
                 e.message

    bad = File.join @tempdir, 'bad'
    FileUtils.touch bad

    e = assert_raises OptionParser::InvalidArgument do
      @cmd.handle_options %W[--certificate #{bad}]
    end

    assert_equal "invalid argument: " +
                 "--certificate #{bad}: invalid X509 certificate",
                 e.message
  end

  def test_handle_options_key_bad
    nonexistent = File.join @tempdir, 'nonexistent'
    e = assert_raises OptionParser::InvalidArgument do
      @cmd.handle_options %W[--private-key #{nonexistent}]
    end

    assert_equal "invalid argument: " +
                 "--private-key #{nonexistent}: does not exist",
                 e.message

    bad = File.join @tempdir, 'bad'
    FileUtils.touch bad

    e = assert_raises OptionParser::InvalidArgument do
      @cmd.handle_options %W[--private-key #{bad}]
    end

    assert_equal "invalid argument: --private-key #{bad}: invalid RSA key",
                 e.message

    e = assert_raises OptionParser::InvalidArgument do
      @cmd.handle_options %W[--private-key #{PUBLIC_KEY_FILE}]
    end

    assert_equal "invalid argument: " +
                 "--private-key #{PUBLIC_KEY_FILE}: private key not found",
                 e.message
  end

  def test_handle_options_sign
    @cmd.handle_options %W[
      --private-key #{ALTERNATE_KEY_FILE}
      --private-key #{PRIVATE_KEY_FILE}

      --certificate #{ALTERNATE_CERT_FILE}
      --certificate #{PUBLIC_CERT_FILE}

      --sign #{ALTERNATE_CERT_FILE}
      --sign #{CHILD_CERT_FILE}
    ]

    assert_equal PRIVATE_KEY.to_pem, @cmd.options[:key].to_pem
    assert_equal PUBLIC_CERT.to_pem, @cmd.options[:issuer_cert].to_pem

    assert_equal [ALTERNATE_CERT_FILE, CHILD_CERT_FILE], @cmd.options[:sign]
  end

  def test_handle_options_sign_encrypted_key
    @cmd.handle_options %W[
      --private-key #{ALTERNATE_KEY_FILE}
      --private-key #{ENCRYPTED_PRIVATE_KEY_PATH}

      --certificate #{ALTERNATE_CERT_FILE}
      --certificate #{PUBLIC_CERT_FILE}

      --sign #{ALTERNATE_CERT_FILE}
      --sign #{CHILD_CERT_FILE}
    ]

    assert_equal ENCRYPTED_PRIVATE_KEY.to_pem, @cmd.options[:key].to_pem
    assert_equal PUBLIC_CERT.to_pem, @cmd.options[:issuer_cert].to_pem

    assert_equal [ALTERNATE_CERT_FILE, CHILD_CERT_FILE], @cmd.options[:sign]
  end

  def test_handle_options_sign_nonexistent
    nonexistent = File.join @tempdir, 'nonexistent'
    e = assert_raises OptionParser::InvalidArgument do
      @cmd.handle_options %W[
        --private-key #{ALTERNATE_KEY_FILE}

        --certificate #{ALTERNATE_CERT_FILE}

        --sign #{nonexistent}
      ]
    end

    assert_equal "invalid argument: --sign #{nonexistent}: does not exist",
                 e.message
  end

end if defined?(OpenSSL::SSL) && !Gem.java_platform?
