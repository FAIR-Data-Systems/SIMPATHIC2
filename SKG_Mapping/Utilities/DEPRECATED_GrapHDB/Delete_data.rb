require 'rest-client'
require 'base64'

def drop_simpathic_graphs(repo_id: 'simpathic-skg', base_url: 'http://57.128.119.57:9001/')
  # Encode credentials for Basic Auth
  abort "ENV['SIMP_GDB_USER'] : ENV['SIMP_GDB_PASS']" unless ENV["SIMP_GDB_USER"]
  auth_header = "Basic #{Base64.strict_encode64("#{ENV["SIMP_GDB_USER"]}:#{ENV["SIMP_GDB_PASS"]}")}"
  
  sparql = <<~SPARQL
    DELETE {
      GRAPH ?g { ?s ?p ?o }
    }
    WHERE {
      GRAPH ?g { ?s ?p ?o }
      FILTER(CONTAINS(STR(?g), "simpathic"))
    }
  SPARQL

  response = RestClient.post(
    "#{base_url}/repositories/#{repo_id}/statements",
    { update: sparql },
    content_type: 'application/x-www-form-urlencoded',
    authorization: auth_header
  )
  puts "Dropped graphs containing 'simpathic': #{response.code}"
rescue RestClient::ExceptionWithResponse => e
  puts "Error: #{e.response}"
end

# Usage
drop_simpathic_graphs('myrepo', 'http://localhost:7200', 'admin', 'your_password')