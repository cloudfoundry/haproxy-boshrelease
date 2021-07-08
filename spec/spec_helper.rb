# frozen_string_literal: true

require 'bosh/template/test'
require 'base64'
require 'zlib'
require 'stringio'
require 'rubygems/package'
require 'deep_merge'

module SharedContext
  extend RSpec::SharedContext

  let(:release_path) { File.join(File.dirname(__FILE__), '..') }
  let(:release) { Bosh::Template::Test::ReleaseDir.new(release_path) }
  let(:haproxy_job) { release.job('haproxy') }
  let(:template) { haproxy_job.template('config/haproxy.config') }
end

RSpec.configure do |config|
  config.include SharedContext
end

RSpec::Matchers.define :be_a_blank_string do
  match do |thing|
    thing =~ /^\s*$/
  end
end

def gzip_and_b64_encode(input)
  io = StringIO.new
  gz = Zlib::GzipWriter.new(io)
  gz.write(input)
  gz.close
  Base64.encode64(io.string)
end

# extracts entry from ttar format
# https://github.com/ideaship/ttar
def ttar_entry(ttar, path)
  entries = ttar.split(/========================== 0600 (.*)/)
  paths = []
  entries.each.with_index do |e, i|
    return entries[i + 1] if e == path

    paths.push(e) if e =~ %r{/var/vcap}
  end

  raise "Entry #{path} not found in ttar, found: #{paths.inspect}"
end

# converts haproxy config into hash of arrays grouped
# by top-level values eg
# {
#    "global" => [
#       "nbproc 4",
#       "daemon",
#       "stats timeout 2m"
#    ]
# }
def parse_haproxy_config(config) # rubocop:disable Metrics/AbcSize
  # remove comments and empty lines
  config = config.split(/\n/).reject { |l| l.empty? || l =~ /^\s*#.*$/ }.join("\n")

  # split into top-level groups
  config.split(/^([^\s].*)/).drop(1).each_slice(2).map do |group|
    key = group[0]
    properties = group[1]

    # remove empty lines
    properties = properties.split(/\n/).reject(&:empty?).join("\n")

    # split and strip leading/trailing whitespace
    properties = properties.split(/\n/).map(&:strip)

    [key, properties]
  end.to_h
end
