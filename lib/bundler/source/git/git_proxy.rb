# frozen_string_literal: true

require "shellwords"

module Bundler
  class Source
    class Git
      class GitNotInstalledError < GitError
        def initialize
          msg = String.new
          msg << "You need to install git to be able to use gems from git repositories. "
          msg << "For help installing git, please refer to GitHub's tutorial at https://help.github.com/articles/set-up-git"
          super msg
        end
      end

      class GitNotAllowedError < GitError
        def initialize(command)
          msg = String.new
          msg << "Bundler is trying to run a `git #{command}` at runtime. You probably need to run `bundle install`. However, "
          msg << "this error message could probably be more useful. Please submit a ticket at https://github.com/bundler/bundler/issues "
          msg << "with steps to reproduce as well as the following\n\nCALLER: #{caller.join("\n")}"
          super msg
        end
      end

      class GitCommandError < GitError
        attr_reader :command

        def initialize(command, path = nil, extra_info = nil)
          @command = command

          msg = String.new
          msg << "Git error: command `git #{command}` in directory #{SharedHelpers.pwd} has failed."
          msg << "\n#{extra_info}" if extra_info
          msg << "\nIf this error persists you could try removing the cache directory '#{path}'" if path && path.exist?
          super msg
        end
      end

      class MissingGitRevisionError < GitCommandError
        def initialize(command, path, ref, repo)
          msg = "Revision #{ref} does not exist in the repository #{repo}. Maybe you misspelled it?"
          super command, path, msg
        end
      end

      # The GitProxy is responsible to interact with git repositories.
      # All actions required by the Git source is encapsulated in this
      # object.
      class GitProxy
        attr_accessor :path, :uri, :ref
        attr_writer :revision

        def initialize(path, uri, ref, revision = nil, git = nil)
          @path     = path
          @uri      = uri
          @ref      = ref
          @revision = revision
          @git      = git
          raise GitNotInstalledError.new if allow? && !Bundler.git_present?
        end

        def revision
          return @revision if @revision

          begin
            @revision ||= find_local_revision
          rescue GitCommandError => e
            raise MissingGitRevisionError.new(e.command, path, ref, URICredentialsFilter.credential_filtered_uri(uri))
          end

          @revision
        end

        def branch
          @branch ||= allowed_in_path do
            git("rev-parse --abbrev-ref HEAD").strip
          end
        end

        def contains?(commit)
          allowed_in_path do
            result, status = git_null("branch --contains #{commit}")
            status.success? && result =~ /^\* (.*)$/
          end
        end

        def version
          git("--version").match(/(git version\s*)?((\.?\d+)+).*/)[2]
        end

        def full_version
          git("--version").sub("git version", "").strip
        end

        def checkout
          return if path.exist? && has_revision_cached?
          extra_ref = "#{Shellwords.shellescape(ref)}:#{Shellwords.shellescape(ref)}" if ref && ref.start_with?("refs/")

          Bundler.ui.info "Fetching #{URICredentialsFilter.credential_filtered_uri(uri)}"

          unless path.exist?
            SharedHelpers.filesystem_access(path.dirname) do |p|
              FileUtils.mkdir_p(p)
            end
            git_retry %(clone #{uri_escaped_with_configured_credentials} "#{path}" --bare --no-hardlinks --quiet)
            return unless extra_ref
          end

          in_path do
            git_retry %(fetch --force --quiet --tags #{uri_escaped_with_configured_credentials} "refs/heads/*:refs/heads/*" #{extra_ref})
          end
        end

        def copy_to(destination, submodules = false)
          # method 1
          unless File.exist?(destination.join(".git"))
            begin
              SharedHelpers.filesystem_access(destination.dirname) do |p|
                FileUtils.mkdir_p(p)
              end
              SharedHelpers.filesystem_access(destination) do |p|
                FileUtils.rm_rf(p)
              end
              git_retry %(clone --no-checkout --quiet "#{path}" "#{destination}")
              File.chmod(((File.stat(destination).mode | 0o777) & ~File.umask), destination)
            rescue Errno::EEXIST => e
              file_path = e.message[%r{.*?(/.*)}, 1]
              raise GitError, "Bundler could not install a gem because it needs to " \
                "create a directory, but a file exists - #{file_path}. Please delete " \
                "this file and try again."
            end
          end
          # method 2
          SharedHelpers.chdir(destination) do
            git_retry %(fetch --force --quiet --tags "#{path}")

            begin
              git "reset --hard #{@revision}"
            rescue GitCommandError => e
              raise MissingGitRevisionError.new(e.command, path, @revision, URICredentialsFilter.credential_filtered_uri(uri))
            end

            if submodules
              git_retry "submodule update --init --recursive"
            elsif Gem::Version.create(version) >= Gem::Version.create("2.9.0")
              git_retry "submodule deinit --all --force"
            end
          end
        end

      private

        def git_null(command)
          command_with_no_credentials = URICredentialsFilter.credential_filtered_string(command, uri)
          raise GitNotAllowedError.new(command_with_no_credentials) unless allow?

          out, status = SharedHelpers.with_clean_git_env do
            capture_and_ignore_stderr("git #{command}")
          end

          [URICredentialsFilter.credential_filtered_string(out, uri), status]
        end

        def git_retry(command)
          Bundler::Retry.new("`git #{URICredentialsFilter.credential_filtered_string(command, uri)}`", GitNotAllowedError).attempts do
            git(command)
          end
        end

        def git(command, check_errors = true, error_msg = nil)
          command_with_no_credentials = URICredentialsFilter.credential_filtered_string(command, uri)
          raise GitNotAllowedError.new(command_with_no_credentials) unless allow?

          out, status = SharedHelpers.with_clean_git_env do
            capture_and_filter_stderr(uri, "git #{command}")
          end

          stdout_with_no_credentials = URICredentialsFilter.credential_filtered_string(out, uri)
          raise GitCommandError.new(command_with_no_credentials, path, error_msg) if check_errors && !status.success?
          stdout_with_no_credentials
        end

        def has_revision_cached?
          return unless @revision
          in_path { git("cat-file -e #{@revision}") }
          true
        rescue GitError
          false
        end

        def remove_cache
          FileUtils.rm_rf(path)
        end

        def find_local_revision
          allowed_in_path do
            git("rev-parse --verify #{Shellwords.shellescape(ref)}", true).strip
          end
        end

        # Escape the URI for git commands
        def uri_escaped_with_configured_credentials
          remote = configured_uri_for(uri)
          if Bundler::WINDOWS
            # Windows quoting requires double quotes only, with double quotes
            # inside the string escaped by being doubled.
            '"' + remote.gsub('"') { '""' } + '"'
          else
            # Bash requires single quoted strings, with the single quotes escaped
            # by ending the string, escaping the quote, and restarting the string.
            "'" + remote.gsub("'") { "'\\''" } + "'"
          end
        end

        # Adds credentials to the URI as Fetcher#configured_uri_for does
        def configured_uri_for(uri)
          if /https?:/ =~ uri
            remote = Bundler::URI(uri)
            config_auth = Bundler.settings[remote.to_s] || Bundler.settings[remote.host]
            remote.userinfo ||= config_auth
            remote.to_s
          else
            uri
          end
        end

        def allow?
          @git ? @git.allow_git_ops? : true
        end

        def in_path(&blk)
          checkout unless path.exist?
          _ = URICredentialsFilter # load it before we chdir
          SharedHelpers.chdir(path, &blk)
        end

        def allowed_in_path
          return in_path { yield } if allow?
          raise GitError, "The git source #{uri} is not yet checked out. Please run `bundle install` before trying to start your application"
        end

        def capture_and_filter_stderr(uri, cmd)
          require "open3"
          return_value, captured_err, status = Open3.capture3(cmd)
          Bundler.ui.warn URICredentialsFilter.credential_filtered_string(captured_err, uri) if uri && !captured_err.empty?
          [return_value, status]
        end

        def capture_and_ignore_stderr(cmd)
          require "open3"
          return_value, _, status = Open3.capture3(cmd)
          [return_value, status]
        end
      end
    end
  end
end
