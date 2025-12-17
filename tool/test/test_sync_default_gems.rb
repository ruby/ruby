#!/usr/bin/ruby
require 'test/unit'
require 'stringio'
require 'tmpdir'
require 'rubygems/version'
require_relative '../sync_default_gems'

module Test_SyncDefaultGems
  class TestMessageFilter < Test::Unit::TestCase
    def assert_message_filter(expected, trailers, input, repo = "ruby/test", sha = "0123456789")
      subject, *expected = expected
      expected = [
        "[#{repo}] #{subject}\n",
        *expected.map {_1+"\n"},
        "\n",
        "https://github.com/#{repo}/commit/#{sha[0, 10]}\n",
      ]
      if trailers
        expected << "\n"
        expected.concat(trailers.map {_1+"\n"})
      end

      out = SyncDefaultGems.message_filter(repo, sha, input)
      assert_pattern_list(expected, out)
    end

    def test_subject_only
      expected = [
        "initial commit",
      ]
      assert_message_filter(expected, nil, "initial commit")
    end

    def test_link_in_parenthesis
      expected = [
        "fix (https://github.com/ruby/test/pull/1)",
      ]
      assert_message_filter(expected, nil, "fix (#1)")
    end

    def test_co_authored_by
      expected = [
        "commit something",
      ]
      trailers = [
        "Co-Authored-By: git <git@ruby-lang.org>",
      ]
      assert_message_filter(expected, trailers, [expected, "", trailers, ""].join("\n"))
    end

    def test_multiple_co_authored_by
      expected = [
        "many commits",
      ]
      trailers = [
        "Co-authored-by: git <git@ruby-lang.org>",
        "Co-authored-by: svn <svn@ruby-lang.org>",
      ]
      assert_message_filter(expected, trailers, [expected, "", trailers, ""].join("\n"))
    end

    def test_co_authored_by_no_newline
      expected = [
        "commit something",
      ]
      trailers = [
        "Co-Authored-By: git <git@ruby-lang.org>",
      ]
      assert_message_filter(expected, trailers, [expected, "", trailers].join("\n"))
    end

    def test_dot_ending_subject
      expected = [
        "subject with a dot.",
        "",
        "- next body line",
      ]
      assert_message_filter(expected, nil, [expected[0], expected[2], ""].join("\n"))
    end
  end

  class TestSyncWithCommits < Test::Unit::TestCase
    def setup
      super
      @target = nil
      pend "No git" unless system("git --version", out: IO::NULL)
      @testdir = Dir.mktmpdir("sync")
      user, email = "Ruby", "test@ruby-lang.org"
      @git_config = %W"HOME USER GIT_CONFIG_GLOBAL GNUPGHOME".each_with_object({}) {|k, c| c[k] = ENV[k]}
      ENV["HOME"] = @testdir
      ENV["USER"] = user
      ENV["GNUPGHOME"] = @testdir + '/.gnupg'
      expire = EnvUtil.apply_timeout_scale(30).to_i
      # Generate a new unprotected key with default parameters that
      # expires after 30 seconds.
      if @gpgsign = system(*%w"gpg --quiet --batch --passphrase", "",
                           "--quick-generate-key", email, *%W"default default seconds=#{expire}",
                           err: IO::NULL)
        # Fetch the generated public key.
        signingkey = IO.popen(%W"gpg --quiet --list-public-key #{email}", &:read)[/^pub .*\n +\K\h+/]
      end
      ENV["GIT_CONFIG_GLOBAL"] = @testdir + "/gitconfig"
      git(*%W"config --global user.email", email)
      git(*%W"config --global user.name", user)
      git(*%W"config --global init.defaultBranch default")
      if signingkey
        git(*%W"config --global user.signingkey", signingkey)
        git(*%W"config --global commit.gpgsign true")
        git(*%W"config --global gpg.program gpg")
        git(*%W"config --global log.showSignature true")
      end
      @target = "sync-test"
      SyncDefaultGems::REPOSITORIES[@target] = SyncDefaultGems.repo(
        ["ruby/#{@target}", "default"],
        [
          ["lib", "lib"],
          ["test", "test"],
        ],
        exclude: [
          "test/fixtures/*",
        ],
      )
      @sha = {}
      @origdir = Dir.pwd
      Dir.chdir(@testdir)
      ["src", @target].each do |dir|
        git(*%W"init -q #{dir}")
        File.write("#{dir}/.gitignore", "*~\n")
        Dir.mkdir("#{dir}/lib")
        File.write("#{dir}/lib/common.rb", ":ok\n")
        Dir.mkdir("#{dir}/.github")
        Dir.mkdir("#{dir}/.github/workflows")
        File.write("#{dir}/.github/workflows/default.yml", "default:\n")
        git(*%W"add .gitignore lib/common.rb .github", chdir: dir)
        git(*%W"commit -q -m", "Initialize", chdir: dir)
        if dir == "src"
          File.write("#{dir}/lib/fine.rb", "return\n")
          Dir.mkdir("#{dir}/test")
          File.write("#{dir}/test/test_fine.rb", "return\n")
          git(*%W"add lib/fine.rb test/test_fine.rb", chdir: dir)
          git(*%W"commit -q -m", "Looks fine", chdir: dir)
        end
        Dir.mkdir("#{dir}/tool")
        File.write("#{dir}/tool/ok", "#!/bin/sh\n""echo ok\n")
        git(*%W"add tool/ok", chdir: dir)
        git(*%W"commit -q -m", "Add tool #{dir}", chdir: dir)
        @sha[dir] = top_commit(dir)
      end
      git(*%W"remote add #{@target} ../#{@target}", chdir: "src")
    end

    def teardown
      if @target
        if @gpgsign
          system(*%W"gpgconf --kill all")
        end
        Dir.chdir(@origdir)
        SyncDefaultGems::REPOSITORIES.delete(@target)
        ENV.update(@git_config)
        FileUtils.rm_rf(@testdir)
      end
      super
    end

    def capture_process_output_to(outputs)
      return yield unless outputs&.empty? == false
      IO.pipe do |r, w|
        orig = outputs.map {|out| out.dup}
        outputs.each {|out| out.reopen(w)}
        w.close
        reader = Thread.start {r.read}
        yield
      ensure
        outputs.each {|out| o = orig.shift; out.reopen(o); o.close}
        return reader.value
      end
    end

    def capture_process_outputs
      out = err = nil
      synchronize do
        out = capture_process_output_to(STDOUT) do
          err = capture_process_output_to(STDERR) do
            yield
          end
        end
      end
      return out, err
    end

    def git(*commands, **opts)
      system("git", *commands, exception: true, **opts)
    end

    def top_commit(dir, format: "%H")
      IO.popen(%W[git log --no-show-signature --format=#{format} -1], chdir: dir, &:read)&.chomp
    end

    def assert_sync(commits = true, success: true, editor: nil)
      result = nil
      out = capture_process_output_to([STDOUT, STDERR]) do
        Dir.chdir("src") do
          orig_editor = ENV["GIT_EDITOR"]
          ENV["GIT_EDITOR"] = editor || 'false'
          edit = true if editor

          result = SyncDefaultGems.sync_default_gems_with_commits(@target, commits, edit: edit)
        ensure
          ENV["GIT_EDITOR"] = orig_editor
        end
      end
      assert_equal(success, result, out)
      out
    end

    def test_sync
      File.write("#@target/lib/common.rb", "# OK!\n")
      git(*%W"commit -q -m", "OK", "lib/common.rb", chdir: @target)
      out = assert_sync()
      assert_not_equal(@sha["src"], top_commit("src"), out)
      assert_equal("# OK!\n", File.read("src/lib/common.rb"))
      log = top_commit("src", format: "%B").lines
      assert_equal("[ruby/#@target] OK\n", log.first, out)
      assert_match(%r[/ruby/#{@target}/commit/\h+$], log.last, out)
      assert_operator(top_commit(@target), :start_with?, log.last[/\h+$/], out)
    end

    def test_skip_tool
      git(*%W"rm -q tool/ok", chdir: @target)
      git(*%W"commit -q -m", "Remove tool", chdir: @target)
      out = assert_sync()
      assert_equal(@sha["src"], top_commit("src"), out)
    end

    def test_skip_test_fixtures
      Dir.mkdir("#@target/test")
      Dir.mkdir("#@target/test/fixtures")
      File.write("#@target/test/fixtures/fixme.rb", "")
      git(*%W"add test/fixtures/fixme.rb", chdir: @target)
      git(*%W"commit -q -m", "Add fixtures", chdir: @target)
      out = assert_sync(["#{@sha[@target]}..#{@target}/default"])
      assert_equal(@sha["src"], top_commit("src"), out)
    end

    def test_skip_toplevel
      Dir.mkdir("#@target/docs")
      File.write("#@target/docs/NEWS.md", "= NEWS!!!\n")
      git(*%W"add --", "docs/NEWS.md", chdir: @target)
      File.write("#@target/docs/hello.md", "Hello\n")
      git(*%W"add --", "docs/hello.md", chdir: @target)
      git(*%W"commit -q -m", "It's a news", chdir: @target)
      out = assert_sync()
      assert_equal(@sha["src"], top_commit("src"), out)
    end

    def test_adding_toplevel
      Dir.mkdir("#@target/docs")
      File.write("#@target/docs/NEWS.md", "= New library\n")
      File.write("#@target/lib/news.rb", "return\n")
      git(*%W"add --", "docs/NEWS.md", "lib/news.rb", chdir: @target)
      git(*%W"commit -q -m", "New lib", chdir: @target)
      out = assert_sync()
      assert_not_equal(@sha["src"], top_commit("src"), out)
      assert_equal "return\n", File.read("src/lib/news.rb")
      assert_include top_commit("src", format: "oneline"), "[ruby/#{@target}] New lib"
      assert_not_operator File, :exist?, "src/docs"
    end

    def test_gitignore
      File.write("#@target/.gitignore", "*.bak\n", mode: "a")
      File.write("#@target/lib/common.rb", "Should.be_merged\n", mode: "a")
      File.write("#@target/.github/workflows/main.yml", "# Should not merge\n", mode: "a")
      git(*%W"add .github", chdir: @target)
      git(*%W"commit -q -m", "Should be common.rb only",
          *%W".gitignore lib/common.rb .github", chdir: @target)
      out = assert_sync()
      assert_not_equal(@sha["src"], top_commit("src"), out)
      assert_equal("*~\n", File.read("src/.gitignore"), out)
      assert_equal("#!/bin/sh\n""echo ok\n", File.read("src/tool/ok"), out)
      assert_equal(":ok\n""Should.be_merged\n", File.read("src/lib/common.rb"), out)
      assert_not_operator(File, :exist?, "src/.github/workflows/main.yml", out)
    end

    def test_gitignore_after_conflict
      File.write("src/Gemfile", "# main\n")
      git(*%W"add Gemfile", chdir: "src")
      git(*%W"commit -q -m", "Add Gemfile", chdir: "src")
      File.write("#@target/Gemfile", "# conflict\n", mode: "a")
      File.write("#@target/lib/common.rb", "Should.be_merged\n", mode: "a")
      File.write("#@target/.github/workflows/main.yml", "# Should not merge\n", mode: "a")
      git(*%W"add Gemfile .github lib/common.rb", chdir: @target)
      git(*%W"commit -q -m", "Should be common.rb only", chdir: @target)
      out = assert_sync()
      assert_not_equal(@sha["src"], top_commit("src"), out)
      assert_equal("# main\n", File.read("src/Gemfile"), out)
      assert_equal(":ok\n""Should.be_merged\n", File.read("src/lib/common.rb"), out)
      assert_not_operator(File, :exist?, "src/.github/workflows/main.yml", out)
    end

    def test_delete_after_conflict
      File.write("#@target/lib/bad.rb", "raise\n")
      git(*%W"add lib/bad.rb", chdir: @target)
      git(*%W"commit -q -m", "Add bad.rb", chdir: @target)
      out = assert_sync
      assert_equal("raise\n", File.read("src/lib/bad.rb"))

      git(*%W"rm lib/bad.rb", chdir: "src", out: IO::NULL)
      git(*%W"commit -q -m", "Remove bad.rb", chdir: "src")

      File.write("#@target/lib/bad.rb", "raise 'bar'\n")
      File.write("#@target/lib/common.rb", "Should.be_merged\n", mode: "a")
      git(*%W"add lib/bad.rb lib/common.rb", chdir: @target)
      git(*%W"commit -q -m", "Add conflict", chdir: @target)

      head = top_commit("src")
      out = assert_sync(editor: "git rm -f lib/bad.rb")
      assert_not_equal(head, top_commit("src"))
      assert_equal(":ok\n""Should.be_merged\n", File.read("src/lib/common.rb"), out)
      assert_not_operator(File, :exist?, "src/lib/bad.rb", out)
    end

    def test_squash_merge
      # This test is known to fail with git 2.43.0, which is used by Ubuntu 24.04.
      # We don't know which exact version fixed it, but we know git 2.52.0 works.
      stdout, status = Open3.capture2('git', '--version', err: File::NULL)
      omit 'git version check failed' unless status.success?
      git_version = stdout.rstrip.delete_prefix('git version ')
      omit "git #{git_version} is too old" if Gem::Version.new(git_version) < Gem::Version.new('2.44.0')

      #   2---.   <- branch
      #  /     \
      # 1---3---3'<- merge commit with conflict resolution
      File.write("#@target/lib/conflict.rb", "# 1\n")
      git(*%W"add lib/conflict.rb", chdir: @target)
      git(*%W"commit -q -m", "Add conflict.rb", chdir: @target)

      git(*%W"checkout -q -b branch", chdir: @target)
      File.write("#@target/lib/conflict.rb", "# 2\n")
      File.write("#@target/lib/new.rb", "# new\n")
      git(*%W"add lib/conflict.rb lib/new.rb", chdir: @target)
      git(*%W"commit -q -m", "Commit in branch", chdir: @target)

      git(*%W"checkout -q default", chdir: @target)
      File.write("#@target/lib/conflict.rb", "# 3\n")
      git(*%W"add lib/conflict.rb", chdir: @target)
      git(*%W"commit -q -m", "Commit in default", chdir: @target)

      # How can I suppress "Auto-merging ..." message from git merge?
      git(*%W"merge -X ours -m", "Merge commit", "branch", chdir: @target, out: IO::NULL)

      out = assert_sync()
      assert_equal("# 3\n", File.read("src/lib/conflict.rb"), out)
      subject, body = top_commit("src", format: "%B").split("\n\n", 2)
      assert_equal("[ruby/#@target] Merge commit", subject, out)
      assert_includes(body, "Commit in branch", out)
    end

    def test_no_upstream_file
      group = SyncDefaultGems::Repository.group(%w[
          lib/un.rb
          lib/unicode_normalize/normalize.rb
          lib/unicode_normalize/tables.rb
          lib/net/https.rb
      ])
      expected = {
        "un" => %w[lib/un.rb],
        "net-http" => %w[lib/net/https.rb],
        nil => %w[lib/unicode_normalize/normalize.rb lib/unicode_normalize/tables.rb],
      }
      assert_equal(expected, group)
    end
  end if /darwin|linux/ =~ RUBY_PLATFORM
end
