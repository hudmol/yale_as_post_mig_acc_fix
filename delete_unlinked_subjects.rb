require 'net/http'
require 'json'
require 'uri'
require 'optparse'
require 'logger'

class UnlinkedSubjectDeleter

  def initialize(opts, log)
    @backend_url = URI.parse(opts[:backend_url])
    @username = opts[:username]
    @password = opts[:password]
    @commit = opts[:commit] || false
    @session = nil

    @log = log
    @log.info { "Initialized UnlinkedSubjectDeleter with options:" }
    @log.info { "  backend_url: #{@backend_url}" }
    @log.info { "  username:    #{@username}" }
    @log.info { "  password:    ---" }
    @log.info { "  commit:      #{@commit}" }
  end


  def run
    ensure_session

    response = get_request("/subjects", {'all_ids' => 'true'})
    raise "Error: #{response.body}" unless response.code == '200'
    all_ids = JSON.parse(response.body)

    all_ids.each_slice(50) do |page_ids|
      response = get_request("/subjects", {'id_set' => page_ids.join(",")})

      JSON.parse(response.body).each do |subj|
        @log.info { "Subject #{subj['uri']} #{subj['title']}" }
        @log.debug { subj }
        lr_resp = get_request("/search", { 'page' => 1, 'filter_term[]' => { "subjects" => subj['title'] }.to_json })
        if lr_resp.code == '200'
          linked_records = JSON.parse(lr_resp.body)
          if linked_records['total_hits'] == 0
            if @commit
              @log.info "Subject is no longer linked to any records, so deleting"
              del_resp = delete_request(subj['uri'])
              if del_resp.code == '200'
                @log.info { "Deleted #{subj['uri']}" }
              else
                @log.error { "Failed to delete subject #{subj['uri']}: #{del_resp.code} #{del_resp.body}" }
              end
            else
              @log.info "Subject is no longer linked to any records, skipping delete (commit is false)"
            end
          else
            @log.info { "Subject still has #{linked_records['total_hits']} records linking to it, so not deleting" }
          end
        else
          @log.error { "Subject search failed: #{response.body}" }
        end
      end
    end
  end


  private

  def ensure_session
    return if @session

    response = Net::HTTP.post_form(URI.join(@backend_url, "/users/#{@username}/login"),
                                   'password' => @password)

    raise "Login failed" unless response.code == '200'

    @session = JSON.parse(response.body)['session']
  end


  def get_request(uri, data = nil)
    http = Net::HTTP.new(@backend_url.host, @backend_url.port)
    request = Net::HTTP::Get.new(uri)
    request['X-ArchivesSpace-Session'] = @session
    request.set_form_data(data) if data
    http.request(request)
  end


  def delete_request(uri)
    @log.debug { "deleting #{uri}" }
    http = Net::HTTP.new(@backend_url.host, @backend_url.port)
    request = Net::HTTP::Delete.new(uri)
    request['X-ArchivesSpace-Session'] = @session
    http.request(request)
  end

end


###

log = Logger.new(STDOUT)
log.level = Logger::INFO

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: delete_unlinked_subjects.rb [options]"

  opts.on('-a', '--backendurl URL', 'ArchivesSpace backend URL') { |v| options[:backend_url] = v }
  opts.on('-u', '--username USERNAME', 'Username for backend session') { |v| options[:username] = v }
  opts.on('-p', '--password PASSWORD', 'Password for backend session') { |v| options[:password] = v }

  opts.on('-c', '--commit', 'Commit changes to the database') { |v| options[:commit] = v }

  opts.on('-q', '--quiet', 'Only log warnings and errors') { log.level = Logger::WARN  }
  opts.on('-d', '--debug', 'Log debugging output') { log.level = Logger::DEBUG  }

  opts.on("-h", "--help", "Prints this help") { puts opts; exit }
end.parse!

default_options = eval(File.open('config.rb').read)
options = default_options.merge(options)

unless options[:backend_url]
  puts("Please specify a backend_url")
  exit
end

unless options[:username]
  puts("Please specify a username")
  exit
end

unless options[:password]
  puts("Please specify a password")
  exit
end

UnlinkedSubjectDeleter.new(options, log).run
