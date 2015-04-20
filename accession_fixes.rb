require 'net/http'
require 'json'
require 'uri'
require 'pp'
require 'yaml'
require 'optparse'
require 'logger'

class AccessionFixer

  def initialize(opts, log)
    @backend_url = URI.parse(opts[:backend_url])
    @username = opts[:username]
    @password = opts[:password]
    @commit = opts[:commit] || false
    @session = nil

    @log = log
    @log.info { "Initialized AccessionFixer with options:" }
    @log.info { "  backend_url: #{@backend_url}" }
    @log.info { "  username:    #{@username}" }
    @log.info { "  password:    ---" }
    @log.info { "  commit:      #{@commit}" }
  end


  def fix_brbl(code)
    @fund_codes = get_enumeration('payment_fund_code')
    @log.debug { "found fund codes: #{@fund_codes.inspect}" }

    @delete_if_unlinked = {}

    fix(:brbl, code)

    # this is flawed because we can't count on the indexer to have caught up
    @log.debug "checking for unlinked subjects to delete"
    if @commit
      @delete_if_unlinked.each_pair do |ref, title|
        @log.debug { "checking #{ref} #{title}" }
        response = get_request("#{@repo_uri}/search", { 'page' => 1, 'filter_term[]' => { "subjects" => title }.to_json })
        if response.code == '200'
          results = JSON.parse(response.body)
          if results['total_hits'] == 0
            @log.debug "subject is no longer linked to any records, so deleting"
            del_resp = delete_request(ref)
            if del_resp.code == '200'
              @log.info { "Deleted #{ref}" }
            else
              @log.error { "Failed to delete subject #{ref}: #{del_resp.code} #{del_resp.body}" }
            end
          else
            @log.debug { "subject still has #{results['total_hits']} records linking to it, so not deleting" }
          end
        else
          @log.error { "Subject search failed: #{response.body}" }
        end
      end
    else
      @log.debug "skipping subject delete (commit is false)"
    end

  end


  def fix_mssa(code)
    fix(:mssa, code)
  end


  private

  def fix(repo, code)
    @log.info "Running #{repo} fixes for #{code}"
    ensure_session

    @repo_uri = repo_for_code(code)

    page = 1

    while true
      @log.debug "page #{page}"

      response = get_request("#{@repo_uri}/accessions", {'page' => page})

      raise "Error: #{response.body}" unless response.code == '200'

      results = JSON.parse(response.body)

      results['results'].each do |acc|
        @log.info { "Accession #{acc['uri']} #{acc['display_string']}" }

        changed, deletes = apply_mssa(acc) if repo == :mssa
        changed, deletes = apply_brbl(acc) if repo == :brbl

        # save
        if changed
          @log.debug { "record has changed: #{acc}" }
          if @commit
            @log.debug "saving #{acc.inspect}"
            http = Net::HTTP.new(@backend_url.host, @backend_url.port)
            request = Net::HTTP::Post.new(acc['uri'])
            request['X-ArchivesSpace-Session'] = @session
            request.body = acc.to_json
            response = http.request(request)
            if response.code == '200'
              @log.info { "Saved #{acc['uri']}" }

              # only do deletes if we successfully saved - don't want to lose data
              unless deletes.empty?
                deletes.each do |ref|
                  response = delete_request(ref)
                  if response.code == '200'
                    @log.info { "Deleted #{ref}" }
                  else
                    @log.error { "Failed to delete #{ref} for #{acc['uri']}: #{response.code} #{response.body}" }
                  end
                end
              end

            else
              @log.error { "Failed to save #{acc['uri']}: #{response.code} #{response.body}" }
            end
          else
            @log.debug "skipping save (commit is false)"
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


  def apply_mssa(acc)
    changed = false

    @log.debug "applying rule: boolean_2 > electronic_documents"
    if acc.has_key?('user_defined')
      user_def = acc['user_defined']
      if user_def['boolean_2']
        unless acc['material_types']
          acc['material_types'] = {}
        end
        acc['material_types']['electronic_documents'] = true
        user_def['boolean_2'] = false
        @log.debug "record changed"
        changed = true
      end
    end

    @log.debug "applying rule: real_1 > extent"
    if acc.has_key?('user_defined')
      user_def = acc['user_defined']
      if user_def['real_1']
        extent = {
          'portion' => 'part',
          'number' => user_def['real_1'],
          'extent_type' => 'megabytes'
        }
        acc['extents'] << extent
        user_def.delete('real_1')
        @log.debug "record changed"
        changed = true
      end
    end

    [changed, []]
  end


  def apply_brbl(acc)
    changed = false
    deletes = []

    @log.debug "applying rule: real_1 > payment"
    if acc.has_key?('user_defined')
      user_def = acc['user_defined']
      if user_def.has_key?('real_1')
        payment_summary = {
          'in_lot' => user_def['boolean_1'],
          'total_price' => user_def['real_1'],
          'currency' => user_def['string_3'],
          'payments' => []
        }
        user_def['text_2'].split('|').each do |fund_code|
          fund_code.strip!
          if @fund_codes.include?(fund_code)
            payment_summary['payments'] << {'fund_code' => fund_code}
          else
            payment_summary['payments'] << {'note' => fund_code}
          end
        end
        acc['payment_summary'] = payment_summary
        user_def['boolean_1'] = false
        user_def.delete('real_1')
        user_def.delete('string_3')
        user_def.delete('text_2')
        @log.debug "record changed"
        changed = true
      end
    end


    @log.debug "applying rule: agreement_sent > boolean_1"
    acc['linked_events'].each do |event|
      response = get_request(event['ref'])
      results = JSON.parse(response.body)
      if results['event_type'] == 'agreement_sent'
        acc['user_defined'] ||= {}
        acc['user_defined']['boolean_1'] = true
        @log.debug "record changed"
        changed = true
        @log.debug { "record #{event['ref']} marked for delete" }
        deletes << event['ref']
        break
      end
    end


    @log.debug "applying rule: condition_description > content_description"
    if acc.has_key?('condition_description')
      if acc.has_key?('content_description')
        acc['content_description'] += " \n" + acc['condition_description']
      else
        acc['content_description'] = acc['condition_description']
      end
      acc.delete('condition_description')
      @log.debug "record changed"
      changed = true
    end


    @log.debug "applying rule: rights_transferred > boolean_2"
    acc['linked_events'].each do |event|
      response = get_request(event['ref'])
      results = JSON.parse(response.body)
      if results['event_type'] == 'rights_transferred'
        acc['user_defined'] ||= {}
        acc['user_defined']['boolean_2'] = true
        @log.debug "record changed"
        changed = true
        @log.debug { "record #{event['ref']} marked for delete" }
        deletes << event['ref']
        break
      end
    end


    @log.debug "applying rule: integer_1 > extent"
    if acc.has_key?('user_defined')
      user_def = acc['user_defined']
      if user_def['integer_1']
        extent = {
          'portion' => 'part',
          'number' => user_def['integer_1'],
          'extent_type' => 'manuscript_items'
        }
        acc['extents'] << extent
        user_def.delete('integer_1')
        @log.debug "record changed"
        changed = true
      end
    end


    @log.debug "applying rule: integer_2 > extent"
    if acc.has_key?('user_defined')
      user_def = acc['user_defined']
      if user_def['integer_2']
        extent = {
          'portion' => 'part',
          'number' => user_def['integer_2'],
          'extent_type' => 'non_book_format_items'
        }
        acc['extents'] << extent
        user_def.delete('integer_2')
        @log.debug "record changed"
        changed = true
      end
    end


    @log.debug "applying rule: string_2 > text_1"
    if acc.has_key?('user_defined')
      user_def = acc['user_defined']
      if user_def['string_2']
        user_def['text_1'] = user_def['string_2']
        user_def.delete('string_2')
        @log.debug "record changed"
        changed = true
      end
    end


    @log.debug "applying rule: subject > string_3"
    subjects = []
    acc['subjects'].each do |subject|
      response = get_request(subject['ref'])
      subj = JSON.parse(response.body)
      subjects << subj['title']
      @delete_if_unlinked[subject['ref']] = subj['title']
    end
    unless subjects.empty?
      acc['user_defined'] ||= {}
      acc['user_defined']['string_3'] = subjects.join('; ')
      @log.debug "record changed"
      changed = true
      @log.debug "unlinking subjects"
      acc['subjects'] = []
    end


    @log.debug "enum_2 > mssu"
    acc['user_defined'] ||= {}
    acc['user_defined']['enum_2'] = 'mssu'
    @log.debug "record changed"
    changed = true
    

    [changed, deletes]
  end


  def ensure_session
    return if @session

    response = Net::HTTP.post_form(URI.join(@backend_url, "/users/#{@username}/login"),
                                   'password' => @password)

    raise "Login failed" unless response.code == '200'

    @session = JSON.parse(response.body)['session']
  end


  def repo_for_code(repo_code)
    @log.info "  finding repository for #{repo_code}"
    response = get_request("/search/repositories", { 'page' => 1, 'q' => "title='#{repo_code}'" })
    raise "Error: #{response.body}" unless response.code == '200'
    results = JSON.parse(response.body)
    @log.info "    ... got #{results['results'].first['id']}"
    results['results'].first['id']
  end


  def get_enumeration(name)
    response = get_request('/config/enumerations')
    results = JSON.parse(response.body)
    results.select {|a| a['name'] == name }.first['values']
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
  opts.banner = "Usage: accession_fixes.rb [options]"

  opts.on('-a', '--backendurl URL', 'ArchivesSpace backend URL') { |v| options[:backend_url] = v }
  opts.on('-u', '--username USERNAME', 'Username for backend session') { |v| options[:username] = v }
  opts.on('-p', '--password PASSWORD', 'Password for backend session') { |v| options[:password] = v }

  opts.on('--mssacode CODE', 'Repository code for MSSA') { |v| options[:mssa_code] = v }
  opts.on('--brblcode CODE', 'Repository code for BRBL') { |v| options[:brbl_code] = v }

  opts.on('-m', '--mssa', 'Run MSSA fixes') { |v| options[:fix_mssa] = v }
  opts.on('-b', '--brbl', 'Run BRBL fixes') { |v| options[:fix_brbl] = v }

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

if options[:fix_mssa] && !options[:mssa_code]
  puts("Please specify an mssa_code")
  exit
end

if options[:fix_brbl] && !options[:brbl_code]
  puts("Please specify a brbl_code")
  exit
end

if options[:fix_mssa] || options[:fix_brbl]
  fixer = AccessionFixer.new(options, log)
  fixer.fix_mssa(options[:mssa_code]) if options[:fix_mssa]
  fixer.fix_brbl(options[:brbl_code]) if options[:fix_brbl]
else
  puts "Nothing to do. Please specify -m, -b or both"
end
