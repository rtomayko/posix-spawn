require 'test/unit'
require 'posix-spawn'

class SystemTest < Test::Unit::TestCase
  include POSIX::Spawn

  def test_system
    ret = system("true")
    assert_equal ret, true
    assert_equal $?.exitstatus, 0
  end

  def test_system_nonzero
    ret = system("false")
    assert_equal ret, false
    assert_equal $?.exitstatus, 1
  end

  def test_system_nonzero_via_sh
    ret = system("exit 1")
    assert_equal ret, false
    assert_equal $?.exitstatus, 1
  end

  def test_system_failure
    ret = system("nosuch")
    assert_equal ret, false
  end
end
