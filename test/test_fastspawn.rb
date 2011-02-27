rootdir = File.dirname(File.dirname(__FILE__))
$LOAD_PATH.unshift "#{rootdir}/lib"

require 'test/unit'
require 'fastspawn'

class FastSpawnTest < Test::Unit::TestCase
  def test_fastspawn_defined
    assert defined?(FastSpawn)
  end
end
