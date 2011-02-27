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
end
