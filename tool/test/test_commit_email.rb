require 'test/unit'
require 'shellwords'
require 'tmpdir'
require 'fileutils'
require 'open3'

class TestCommitEmail < Test::Unit::TestCase
  def setup
    @ruby = Dir.mktmpdir
    Dir.chdir(@ruby) do
      git('init', '--initial-branch=master')
      git('config', 'user.name', 'Jóhän Grübél')
      git('config', 'user.email', 'johan@example.com')
      env = { 'GIT_AUTHOR_DATE' => '2025-10-08T12:00:00Z' }
      git('commit', '--allow-empty', '-m', 'New repository initialized by cvs2svn.', env:)
      git('commit', '--allow-empty', '-m', 'Initial revision', env:)
      git('commit', '--allow-empty', '-m', 'version 1.0.0', env:)
    end

    @sendmail = File.join(Dir.mktmpdir, 'sendmail')
    File.write(@sendmail, <<~SENDMAIL)
      #!/usr/bin/env ruby
      puts "---"
      puts STDIN.read
    SENDMAIL
    FileUtils.chmod(0755, @sendmail)

    @commit_email = File.expand_path('../../tool/commit-email.rb', __dir__)
  end

  def test_sendmail_encoding
    Dir.chdir(@ruby) do
      before_rev = git('rev-parse', 'HEAD^').chomp
      long_rev = git('rev-parse', 'HEAD').chomp
      short_rev = long_rev[0...10]

      out, _, status = EnvUtil.invoke_ruby([
        { 'SENDMAIL' => @sendmail }.merge!(gem_env),
        @commit_email, './', 'cvs-admin@ruby-lang.org',
        before_rev, long_rev, 'refs/heads/master',
        '--viewer-uri', 'https://github.com/ruby/ruby/commit/',
        '--error-to', 'cvs-admin@ruby-lang.org',
      ], '', true)

      assert_true(status.success?)
      assert_equal(out, <<~EOS)
        master: #{short_rev} (Jóhän Grübél)
        ---
        X-SVN-Author: =?UTF-8?B?SsOzaMOkbiBHcsO8YsOpbA==?=
        X-SVN-Repository: XXX
        X-SVN-Revision: #{short_rev}
        X-SVN-Commit-Id: #{long_rev}
        Mime-Version: 1.0
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable
        From: =?UTF-8?B?SsOzaMOkbiBHcsO8YsOpbA==?= <noreply@ruby-lang.org>
        To: cvs-admin@ruby-lang.org
        Subject: #{short_rev} (master): version 1.0.0
        J=C3=B3h=C3=A4n Gr=C3=BCb=C3=A9l\t2025-10-08 05:00:00 -0700 (Wed, 08 Oct 2=
        025)

          New Revision: #{short_rev}

          https://github.com/ruby/ruby/commit/#{short_rev}

          Log:
            version 1.0.0=
      EOS
    end
  end

  private

  # Resurrect the gem environment preserved by tool/test/init.rb.
  # This should work as long as you have run `make up` or `make install`.
  def gem_env
    { 'GEM_PATH' => ENV['BUNDLED_GEM_PATH'], 'GEM_HOME' => ENV['BUNDLED_GEM_HOME'] }
  end

  def git(*cmd, env: {})
    out, status = Open3.capture2(env, 'git', *cmd)
    unless status.success?
      raise "git #{cmd.shelljoin}\n#{out}"
    end
    out
  end
end
