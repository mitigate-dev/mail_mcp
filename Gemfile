source "https://rubygems.org"

ruby "3.4.9"

gem "aws-sdk-s3", "~> 1.0"
gem "base64", "~> 0.2"
gem "json-jwt", "~> 1.16"
gem "mail", "~> 2.8"
gem "mcp", "~> 0.14"
gem "puma", "~> 6.0"
gem "rack", "~> 3.0"
gem "securerandom"
gem "sinatra", "~> 4.0"
gem "sinatra-contrib", "~> 4.0"
gem "zeitwerk", "~> 2.7"

group :development do
  gem "dotenv", "~> 3.0"
end

group :development, :test do
  gem "rack-test", "~> 2.1"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.75", require: false
  gem "rubocop-rspec", "~> 3.5", require: false
  gem "webmock", "~> 3.23"
end
