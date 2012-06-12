spec = Gem::Specification.new do |s|
  s.name = 'thin'
  s.version = '1.0.0'
  s.summary = "Thin"
  s.description = %{Simple builder classes for thin.}
  s.files = Dir['lib/**/*.rb'] + Dir['test/**/*.rb']
  s.require_path = 'lib'
  s.has_rdoc = true
  s.extra_rdoc_files = Dir['[A-Z]*']
  s.rdoc_options << '--title' <<  'Thin'
  s.author = "Matt Voss"
  s.email = "mattv@tamu.edu"
  s.homepage = "http://vpr.tamu.edu"
  s.add_dependency('rake')
  s.add_development_dependency('rspec', [">= 2.0.0"])

end

