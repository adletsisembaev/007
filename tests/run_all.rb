# frozen_string_literal: true

# Runs every tests/test_*.rb file.
Dir[File.join(__dir__, 'test_*.rb')].sort.each do |file|
  next if File.basename(file) == 'test_helper.rb'

  require file
end
