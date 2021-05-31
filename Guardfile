# frozen_string_literal: true

guard :rspec, cmd: 'rspec' do
  watch(%r{jobs/(.*)/(.*)/(.*)\.erb$}) { |m| "spec/#{m[1]}/#{m[2]}/#{m[3]}_spec.rb" }

  watch(%r{spec/(.*)$}) { |m| "spec/#{m[1]}" }
end
