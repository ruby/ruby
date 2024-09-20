if /mswin|mingw|cygwin/ =~ RUBY_PLATFORM
  begin
    require 'win32/registry'
  rescue LoadError
  else
    require 'test/unit'
  end
end

if defined?(Win32::Registry)
  class TestWin32Registry < Test::Unit::TestCase
    COMPUTERNAME = 'SYSTEM\\CurrentControlSet\\Control\\ComputerName\\ComputerName'
    VOLATILE_ENVIRONMENT = 'Volatile Environment'

    def test_predefined
      assert_predefined_key Win32::Registry::HKEY_CLASSES_ROOT
      assert_predefined_key Win32::Registry::HKEY_CURRENT_USER
      assert_predefined_key Win32::Registry::HKEY_LOCAL_MACHINE
      assert_predefined_key Win32::Registry::HKEY_USERS
      assert_predefined_key Win32::Registry::HKEY_PERFORMANCE_DATA
      assert_predefined_key Win32::Registry::HKEY_PERFORMANCE_TEXT
      assert_predefined_key Win32::Registry::HKEY_PERFORMANCE_NLSTEXT
      assert_predefined_key Win32::Registry::HKEY_CURRENT_CONFIG
      assert_predefined_key Win32::Registry::HKEY_DYN_DATA
    end

    def test_class_open
      name1, keys1 = Win32::Registry.open(Win32::Registry::HKEY_LOCAL_MACHINE, "SYSTEM") do |reg|
        assert_predicate reg, :open?
        [reg.name, reg.keys]
      end
      name2, keys2 = Win32::Registry::HKEY_LOCAL_MACHINE.open("SYSTEM") do |reg|
        assert_predicate reg, :open?
        [reg.name, reg.keys]
      end
      assert_equal name1, name2
      assert_equal keys1, keys2
    end

    def test_read
      computername = ENV['COMPUTERNAME']
      Win32::Registry::HKEY_LOCAL_MACHINE.open(COMPUTERNAME) do |reg|
        assert_equal computername,  reg['ComputerName']
        assert_equal [Win32::Registry::REG_SZ, computername], reg.read('ComputerName')
        assert_raise(TypeError) {reg.read('ComputerName', Win32::Registry::REG_DWORD)}
      end
    end

    def test_create
      desired = Win32::Registry::KEY_ALL_ACCESS
      option = Win32::Registry::REG_OPTION_VOLATILE
      Win32::Registry::HKEY_CURRENT_USER.open(VOLATILE_ENVIRONMENT, desired) do |reg|
        v = self.class.unused_value(reg)
        begin
          reg.create(v, desired, option) {}
        ensure
          reg.delete_key(v, true)
        end
      end
    end

    def test_write
      desired = Win32::Registry::KEY_ALL_ACCESS
      Win32::Registry::HKEY_CURRENT_USER.open(VOLATILE_ENVIRONMENT, desired) do |reg|
        v = self.class.unused_value(reg)
        begin
          reg.write_s(v, "data")
          assert_equal [Win32::Registry::REG_SZ, "data"], reg.read(v)
          reg.write_i(v, 0x5fe79027)
          assert_equal [Win32::Registry::REG_DWORD, 0x5fe79027], reg.read(v)
        ensure
          reg.delete(v)
        end
      end
    end

    private

    def assert_predefined_key(key)
      assert_kind_of Win32::Registry, key
      assert_predicate key, :open?
      assert_not_predicate key, :created?
    end

    class << self
      def unused_value(reg, prefix = "Test_", limit = 100, fail: true)
        limit.times do
          v =  + rand(0x100000).to_s(36)
          reg.read(v)
        rescue
          return v
        end
        omit "Unused value not found in #{reg}" if fail
      end
    end
  end
end
