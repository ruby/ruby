# frozen_string_literal: true

require "cgi"
require_relative "vendored_thor"

module Bundler
  module FriendlyErrors
  module_function

    def log_error(error)
      case error
      when YamlSyntaxError
        Bundler.ui.error error.message
        Bundler.ui.trace error.orig_exception
      when Dsl::DSLError, GemspecError
        Bundler.ui.error error.message
      when GemRequireError
        Bundler.ui.error error.message
        Bundler.ui.trace error.orig_exception, nil, true
      when BundlerError
        Bundler.ui.error error.message, :wrap => true
        Bundler.ui.trace error
      when Thor::Error
        Bundler.ui.error error.message
      when LoadError
        raise error unless error.message =~ /cannot load such file -- openssl|openssl.so|libcrypto.so/
        Bundler.ui.error "\nCould not load OpenSSL."
        Bundler.ui.warn <<-WARN, :wrap => true
          You must recompile Ruby with OpenSSL support or change the sources in your \
          Gemfile from 'https' to 'http'. Instructions for compiling with OpenSSL \
          using RVM are available at http://rvm.io/packages/openssl.
        WARN
        Bundler.ui.trace error
      when Interrupt
        Bundler.ui.error "\nQuitting..."
        Bundler.ui.trace error
      when Gem::InvalidSpecificationException
        Bundler.ui.error error.message, :wrap => true
      when SystemExit
      when *[defined?(Java::JavaLang::OutOfMemoryError) && Java::JavaLang::OutOfMemoryError].compact
        Bundler.ui.error "\nYour JVM has run out of memory, and Bundler cannot continue. " \
          "You can decrease the amount of memory Bundler needs by removing gems from your Gemfile, " \
          "especially large gems. (Gems can be as large as hundreds of megabytes, and Bundler has to read those files!). " \
          "Alternatively, you can increase the amount of memory the JVM is able to use by running Bundler with jruby -J-Xmx1024m -S bundle (JRuby defaults to 500MB)."
      else request_issue_report_for(error)
      end
    rescue StandardError
      raise error
    end

    def exit_status(error)
      case error
      when BundlerError then error.status_code
      when Thor::Error then 15
      when SystemExit then error.status
      else 1
      end
    end

    def request_issue_report_for(e)
      Bundler.ui.info <<-EOS.gsub(/^ {8}/, "")
        --- ERROR REPORT TEMPLATE -------------------------------------------------------
        # Error Report

        ## Questions

        Please fill out answers to these questions, it'll help us figure out
        why things are going wrong.

        - **What did you do?**

          I ran the command `#{$PROGRAM_NAME} #{ARGV.join(" ")}`

        - **What did you expect to happen?**

          I expected Bundler to...

        - **What happened instead?**

          Instead, what happened was...

        - **Have you tried any solutions posted on similar issues in our issue tracker, stack overflow, or google?**

          I tried...

        - **Have you read our issues document, https://github.com/bundler/bundler/blob/master/doc/contributing/ISSUES.md?**

          ...

        ## Backtrace

        ```
        #{e.class}: #{e.message}
          #{e.backtrace && e.backtrace.join("\n          ").chomp}
        ```

        #{Bundler::Env.report}
        --- TEMPLATE END ----------------------------------------------------------------

      EOS

      Bundler.ui.error "Unfortunately, an unexpected error occurred, and Bundler cannot continue."

      Bundler.ui.warn <<-EOS.gsub(/^ {8}/, "")

        First, try this link to see if there are any existing issue reports for this error:
        #{issues_url(e)}

        If there aren't any reports for this error yet, please create copy and paste the report template above into a new issue. Don't forget to anonymize any private data! The new issue form is located at:
        https://github.com/bundler/bundler/issues/new
      EOS
    end

    def issues_url(exception)
      message = exception.message.lines.first.tr(":", " ").chomp
      message = message.split("-").first if exception.is_a?(Errno)
      "https://github.com/bundler/bundler/search?q=" \
        "#{CGI.escape(message)}&type=Issues"
    end
  end

  def self.with_friendly_errors
    yield
  rescue SignalException
    raise
  rescue Exception => e # rubocop:disable Lint/RescueException
    FriendlyErrors.log_error(e)
    exit FriendlyErrors.exit_status(e)
  end
end
