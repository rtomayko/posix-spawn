require 'test/unit'
require 'posix-spawn'

class SystemTest < Test::Unit::TestCase
  include POSIX::Spawn

  def test_system
    ret = system("exit")
    assert_equal ret, true
    assert_equal $?.exitstatus, 0
  end

  def test_system_nonzero
    ret = system("exit 1")
    assert_equal ret, false
    assert_equal $?.exitstatus, 1
  end

  def test_system_failure
    ret = system("nosuch 2> /dev/null")
    assert_equal ret, false
  end
end
