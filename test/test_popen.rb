require File.expand_path('../helper', __FILE__)

class PopenTest < Test::Unit::TestCase
  include POSIX::Spawn

  def test_popen4
    pid, i, o, e = popen4("cat")
    i.write "hello world"
    i.close
    ::Process.wait(pid)

    assert_equal "hello world", o.read
    assert_equal 0, $?.exitstatus
  ensure
    [i, o, e].each{ |io| io.close rescue nil }
  end
end
