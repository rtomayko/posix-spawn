require 'test/unit'
require 'posix-spawn'

class UtilTest < Test::Unit::TestCase
  include POSIX::Spawn::Util

  def test_bin_sh
    if win?
      assert_equal "sh", bin_sh
    else
      assert_equal "/bin/sh", bin_sh
    end
  end
  
  def test_null
    if win?
      assert_equal "NUL", null
    else
      assert_equal "/dev/null", null
    end
  end
end
