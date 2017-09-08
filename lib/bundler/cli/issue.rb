# frozen_string_literal: true

require "rbconfig"

module Bundler
  class CLI::Issue
    def run
      Bundler.ui.info <<-EOS.gsub(/^ {8}/, "")
        Did you find an issue with Bundler? Before filing a new issue,
        be sure to check out these resources:

        1. Check out our troubleshooting guide for quick fixes to common issues:
        https://github.com/bundler/bundler/blob/master/doc/TROUBLESHOOTING.md

        2. Instructions for common Bundler uses can be found on the documentation
        site: http://bundler.io/

        3. Information about each Bundler command can be found in the Bundler
        man pages: http://bundler.io/man/bundle.1.html

        Hopefully the troubleshooting steps above resolved your problem!  If things
        still aren't working the way you expect them to, please let us know so
        that we can diagnose and help fix the problem you're having. Please
        view the Filing Issues guide for more information:
        https://github.com/bundler/bundler/blob/master/doc/contributing/ISSUES.md

      EOS

      Bundler.ui.info Bundler::Env.new.report

      Bundler.ui.info "\n## Bundle Doctor"
      doctor
    end

    def doctor
      require "bundler/cli/doctor"
      Bundler::CLI::Doctor.new({}).run
    end
  end
end
