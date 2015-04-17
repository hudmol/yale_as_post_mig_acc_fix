require 'net/http'
require 'json'
require 'uri'
require 'pp'
require 'yaml'
require 'optparse'

class AccessionFixer

  def initialize(opts)
    @backend_url = URI.parse(opts[:backend_url])
    @username = opts[:username]
    @password = opts[:password]
    @commit = opts[:commit]
    @session = nil

    log
    log "Initialized with options:"
    log "  backend_url: #{@backend_url}"
    log "  username:    #{@username}"
    log "  password:    #{@password}"
    log "  commit:      #{@commit}"
    log
  end


  def fix(opts = {})
    ensure_session

    repo_id = 2

    page = 1

    while true
      log "page #{page}"
      http = Net::HTTP.new(@backend_url.host, @backend_url.port)
      request = Net::HTTP::Get.new("/repositories/#{repo_id}/accessions")
      request['X-ArchivesSpace-Session'] = @session
      request.set_form_data('page' => page)
      response = http.request(request)

      raise "Error: #{response.body}" unless response.code == '200'

      results = JSON.parse(response.body)

      results['results'].each do |acc|
        log "  Accession #{acc['display_string']}"
        changed = false
        if acc.has_key?('user_defined')
          user_def = acc['user_defined']
          if user_def['boolean_2']
            log "    found boolean_2"
            unless acc['material_types']
              log "      creating material_types record" 
              # create it
              acc['material_types'] = {}
           end
            log "      setting 'electronic_documents' to true"
            acc['material_types']['electronic_documents'] = true
            log "      setting boolean_2 to false"
            user_def['boolean_2'] = false
            changed = true
          end

          if user_def['real_1']
            log "    found real_1"
            log "      adding extent record"
            extent = {
              'portion' => 'part',
              'number' => user_def['real_1'],
              'extent_type' => 'megabytes'
            }
            acc['extents'] << extent
            log "      removing real_1"
            user_def.delete('real_1')
            changed = true
          end

          # save
          if changed
            if @commit
              log "    saving ..."
              http = Net::HTTP.new(@backend_url.host, @backend_url.port)
              request = Net::HTTP::Post.new(acc['uri'])
              request['X-ArchivesSpace-Session'] = @session
              request.body = acc.to_json
              response = http.request(request)
              raise "Error: #{response.body}" unless response.code == '200'
              log "           ... success"
            else
              log "    skipping save (commit is false)"
            end
          end

        end
      end

      if results['this_page'] < results['last_page']
        page += 1
      else
        break
      end
    end

  end


  private

  def log(msg = "")
    puts msg
  end


  def ensure_session
    return if @session

    response = Net::HTTP.post_form(URI.join(@backend_url, "/users/#{@username}/login"),
                                   'password' => @password)

    raise "Login failed" unless response.code == '200'

    @session = JSON.parse(response.body)['session']
  end

end



options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: accession_fixes.rb [options]"

  opts.on('-b', '--backendurl URL', 'Backend URL') { |v| options[:backend_url] = v }
  opts.on('-u', '--username USERNAME', 'Username for backend session') { |v| options[:username] = v }
  opts.on('-p', '--password PASSWORD', 'Password for backend session') { |v| options[:password] = v }

  opts.on('-c', '--commit', 'Commit changes to the database') { |v| options[:commit] = v }

  opts.on("-h", "--help", "Prints this help") { puts opts; exit }
end.parse!

default_options = eval(File.open('config.rb').read)
options = default_options.merge(options)

AccessionFixer.new(options).fix()
