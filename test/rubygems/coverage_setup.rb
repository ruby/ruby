# frozen_string_literal: true

# This file is loaded via -r flag BEFORE rubygems to enable coverage tracking
# of rubygems boot files. It must be used with --disable-gems and -Ilib
# so that Coverage.start runs before rubygems is loaded.

require "coverage"
Coverage.start(lines: true)
require "rubygems"
