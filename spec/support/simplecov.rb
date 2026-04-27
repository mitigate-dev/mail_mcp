if ENV["CI"]
  require "simplecov"
  require "simplecov-cobertura"
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
  SimpleCov.merge_timeout 3600
  SimpleCov.start
end
