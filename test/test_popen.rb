require 'test/unit'
require 'posix-spawn'

class PopenTest < Test::Unit::TestCase
  include POSIX::Spawn

  def test_popen4
    pid, i, o, e = popen4("cat")
    i.write "hello world"
    i.close
    ::Process.wait(pid)

    assert_equal o.read, "hello world"
    assert_equal $?.exitstatus, 0
  ensure
    [i, o, e].each{ |io| io.close rescue nil }
  end
end
