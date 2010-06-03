require 'test/unit'
require_relative 'in_environment'

require 'rake'

class Rake::TestWin32 < Test::Unit::TestCase
  include InEnvironment

  Win32 = Rake::Win32

  def test_win32_system_dir_uses_home_if_defined
    in_environment('RAKE_SYSTEM' => nil,
      'HOME' => "C:\\HP",
      'APPDATA' => nil
      ) do
      assert_equal "C:/HP/Rake", Win32.win32_system_dir
    end
  end

  def test_win32_system_dir_uses_appdata_if_defined
    in_environment(
      'RAKE_SYSTEM' => nil,
      'HOME' => "C:\\HP",
      'APPDATA' => "C:\\Documents and Settings\\HP\\Application Data"
      ) do
      assert_equal "C:/Documents and Settings/HP/Application Data/Rake", Win32.win32_system_dir
    end
  end

  def test_win32_system_dir_nil_of_no_env_vars
    in_environment(
      'RAKE_SYSTEM' => nil,
      'HOME' => nil,
      'HOMEDRIVE' => nil,
      "HOMEPATH" => nil,
      'APPDATA' => nil,
      'USERPROFILE' => "C:\\Documents and Settings\\HP"
      ) do
      assert_raise(ArgumentError) do
        Win32.win32_system_dir
      end
    end
  end

end if Rake::Win32.windows?
