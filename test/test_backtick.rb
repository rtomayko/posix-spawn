require 'test/unit'
require 'posix-spawn'

class BacktickTest < Test::Unit::TestCase
  include POSIX::Spawn

  def test_backtick_simple
    out = `exit`
    assert_equal out, ''
    assert_equal $?.exitstatus, 0
  end

  def test_backtick_output
    out = `echo 123`
    assert_equal out, "123\n"
    assert_equal $?.exitstatus, 0
  end

  def test_backtick_failure
    out = `nosuchcmd 2> /dev/null`
    assert_equal out, ''
    assert_equal $?.exitstatus, 127
  end

  def test_backtick_redirect
    out = `nosuchcmd 2>&1`
    assert_equal out, "/bin/sh: nosuchcmd: command not found\n"
    assert_equal $?.exitstatus, 127
  end
end
