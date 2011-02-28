require 'test/unit'
require 'fastspawn'

class FastSpawnTest < Test::Unit::TestCase
  include FastSpawn

  def test_fastspawn_methods_exposed_at_module_level
    assert FastSpawn.respond_to?(:vspawn)
  end

  def test_vspawn_simple
    pid = vspawn('true')
    assert pid > 0

    chpid, status = Process.wait2
    assert_equal chpid, pid
    assert_equal 0, status.exitstatus
  end

  def test_vspawn_with_argv
    pid = vspawn('true', 'with', 'some arguments')
    assert_process_exit_ok pid
  end

  def test_fspawn
    pid = fspawn('true', 'with', 'some stuff')
    assert_process_exit_ok pid
  end

  def test_pspawn
    pid = pspawn('true', 'with', 'some stuff')
    assert_process_exit_ok pid
  end

  ##
  # Assertion Helpers

  def assert_process_exit_ok(pid)
    assert pid > 0
    chpid, status = Process.wait2
    assert_equal chpid, pid
    assert_equal 0, status.exitstatus
  end

  def test_psawn_error
    assert_raises Errno::ENOENT do
      pspawn('nottrue')
    end
  end
end
