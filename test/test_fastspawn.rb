rootdir = File.dirname(File.dirname(__FILE__))
$LOAD_PATH.unshift "#{rootdir}/lib"

require 'test/unit'
require 'fastspawn'

class FastSpawnTest < Test::Unit::TestCase
  def test_fastspawn_module_defined
    assert defined?(FastSpawn)
  end

  def test_fastspawn_methods_exposed_at_module_level
    assert FastSpawn.respond_to?(:vspawn)
  end

  def test_vspawn_simple
    pid = FastSpawn.vspawn('/bin/true')
    assert pid > 0

    chpid, status = Process.wait2
    assert_equal chpid, pid
    assert_equal 0, status.exitstatus
  end
end
