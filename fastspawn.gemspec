Gem::Specification.new do |s|
  s.name = 'fastspawn'
  s.version = '0.1'
  s.summary = "Fast process spawner"
  s.date = '2011-02-26'
  s.email = 'r@tomayko.com'
  s.homepage = 'http://github.com/rtomayko/fastspawn'
  s.has_rdoc = false
  s.authors = ["Ryan Tomayko", "Aman Gupta"]
  # = MANIFEST =
  s.files = %w[
    COPYING
    README
    Rakefile
    ext/extconf.rb
    fastspawn.gemspec
    lib/fastspawn.rb
  ]
  # = MANIFEST =
  s.test_files = []
  s.extra_rdoc_files = ["COPYING"]
  s.extensions = ["ext/extconf.rb"]
  s.executables = []
  s.require_paths = ["lib"]
end
