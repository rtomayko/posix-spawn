task :default => :test

# ==========================================================
# Packaging
# ==========================================================

GEMSPEC = eval(File.read('posix-spawn.gemspec'))

require 'rubygems/package_task'
Gem::PackageTask.new(GEMSPEC) do |pkg|
end

# ==========================================================
# Ruby Extension
# ==========================================================

require 'rake/extensiontask'
Rake::ExtensionTask.new('posix_spawn_ext', GEMSPEC) do |ext|
  ext.ext_dir = 'ext'
end
task :build => :compile

# ==========================================================
# Testing
# ==========================================================

require 'rake/testtask'
Rake::TestTask.new 'test' do |t|
  t.libs << "test"
  t.test_files = FileList['test/test_*.rb']
end
task :test => :build

desc 'Run some benchmarks'
task :benchmark => :build do
  ruby '-Ilib', 'bin/posix-spawn-benchmark'
end
