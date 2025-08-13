#!/usr/bin/env ruby
require 'rest-client'
require 'base64'
require 'fileutils'
require 'json'
require 'rdf'
require 'rdf/n3' # For N-Quads parsing

# Configuration
USERNAME = ENV['SIMP_GDB_USER']
PASSWORD = ENV['SIMP_GDB_PASS']

# Validate RDF file (N-Quads)
def validate_rdf_file(file_path)
  RDF::Reader.open(file_path, format: :nquads) do |reader|
    reader.each_statement {} # Iterate to trigger parsing
  end
  warn "Validation passed for #{file_path}"
  true
rescue RDF::ReaderError => e
  warn "Validation failed for #{file_path}: #{e.message}"
  false
rescue StandardError => e
  warn "Unexpected error validating #{file_path}: #{e.message}"
  false
end

def load_small_file(file_path, repo_id: 'simpathic-skg', base_url: 'http://57.128.119.57:9001/')
  abort "ENV['SIMP_GDB_USER'] or ENV['SIMP_GDB_PASS'] not set" unless USERNAME && PASSWORD
  auth_header = "Basic #{Base64.strict_encode64(USERNAME + ':' + PASSWORD)}"

  warn "beginning POST of #{file_path} to #{base_url}/repositories/#{repo_id}/statements"
  response = RestClient.post(
    "#{base_url}/repositories/#{repo_id}/statements",
    File.read(file_path),
    content_type: 'application/n-quads', # Use 'application/trig' if TriG, etc.
    authorization: auth_header
  )
  puts "Loaded #{file_path}: #{response.code}"
rescue RestClient::ExceptionWithResponse => e
  puts "Error: #{e.response}"
end

def process_files(load: false)
  if ARGV.empty?
    puts 'Usage: ruby loaddata.rb <file1.nq> <file2.nq> ...'
    exit 1
  end

  ARGV.each_with_index do |file_path, _index|
    warn "processing #{file_path}"
    unless File.exist?(file_path) && (File.extname(file_path) == '.nq' || File.extname(file_path) == '.large') 
      warn "Skipping #{file_path}: File does not exist or is not an .nq or .large file"
      next
    end

    # Validate RDF file before uploading
    unless validate_rdf_file(file_path)
      warn "Skipping upload for #{file_path} due to validation failure"
      next
    end

    load_small_file(file_path) if load
  end
end

# Run
process_files(load: false)
