#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

repo_root = File.expand_path('..', __dir__)
hooks_dir = File.join(repo_root, 'tool', 'hooks')
pre_commit_script = File.join(hooks_dir, 'pre-commit')

unless File.exist?(pre_commit_script)
  puts "Error: Pre-commit hook script not found at #{pre_commit_script}"
  exit 1
end

# Ensure pre-commit script is executable
File.chmod(0755, pre_commit_script)

# Set git config core.hooksPath to tool/hooks
system('git', '-C', repo_root, 'config', 'core.hooksPath', 'tool/hooks')
if $?.success?
  puts "Successfully configured git core.hooksPath to 'tool/hooks'."
  puts "Pre-commit dual-compilation verification is now active."
else
  puts "Error setting git config core.hooksPath."
  exit 1
end
