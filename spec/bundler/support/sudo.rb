# frozen_string_literal: true
module Spec
  module Sudo
    def self.present?
      @which_sudo ||= Bundler.which("sudo")
    end

    def sudo(cmd)
      raise "sudo not present" unless Sudo.present?
      sys_exec("sudo #{cmd}")
    end

    def chown_system_gems_to_root
      sudo "chown -R root #{system_gem_path}"
    end
  end
end
