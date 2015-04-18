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
    @commit = opts[:commit] || false
    @session = nil

    log
    log "Initialized AccessionFixer with options:"
    log "  backend_url: #{@backend_url}"
    log "  username:    #{@username}"
    log "  password:    #{@password}"
    log "  commit:      #{@commit}"
    log
  end


  def fix_brbl(code)
    @fund_codes = get_enumeration('payment_fund_code')
    log "Found fund codes: #{@fund_codes.inspect}"

    fix(:brbl, code)
  end


  def fix_mssa(code)
    fix(:mssa, code)
  end


  private

  def fix(repo, code)
    log "Running #{repo} fixes for #{code}"
    ensure_session

    repo_uri = repo_for_code(code)

    page = 1

    while true
      log "page #{page}"

      response = get_request("#{repo_uri}/accessions", {'page' => page})

      raise "Error: #{response.body}" unless response.code == '200'

      results = JSON.parse(response.body)

      results['results'].each do |acc|
        log "  Accession #{acc['display_string']}"

        changed, deletes = apply_mssa(acc) if repo == :mssa
        changed, deletes = apply_brbl(acc) if repo == :brbl

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

        unless deletes.empty?
          if @commit
            deletes.each do |ref|
              log "    deleting #{ref}"
              response = delete_request(ref)
              if response.code == '200'
                log "      ... success"
              else
                log "ERROR: Failed to delete #{ref} - #{response.body}"
              end
            end
          else
            log "    skipping deletes (commit is false)"
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

    if acc.has_key?('user_defined')
      user_def = acc['user_defined']

      # boolean_2 > electronic_documents
      if user_def['boolean_2']
        log "    found boolean_2"
        unless acc['material_types']
          log "      creating material_types record" 
          acc['material_types'] = {}
        end
        log "      setting 'electronic_documents' to true"
        acc['material_types']['electronic_documents'] = true
        log "      setting boolean_2 to false"
        user_def['boolean_2'] = false
        changed = true
      end

      # real_1 > extent
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
    end

    [changed, []]
  end


  def apply_brbl(acc)
    changed = false
    deletes = []

    # payments
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
        changed = true
      end
    end


    # agreement_sent
    acc['linked_events'].each do |event|
      response = get_request(event['ref'])
      results = JSON.parse(response.body)
      if results['event_type'] == 'agreement_sent'
        acc['user_defined'] ||= {}
        acc['user_defined']['boolean_1'] = true
        changed = true
        deletes << event['ref']
        break
      end
    end


    # condition_description
    if acc.has_key?('condition_description')
      if acc.has_key?('content_description')
        acc['content_description'] += " \n" + acc['condition_description']
      else
        acc['content_description'] = acc['condition_description']
      end
      acc.delete('condition_description')
      changed = true
    end


    # rights_transferred
    acc['linked_events'].each do |event|
      response = get_request(event['ref'])
      results = JSON.parse(response.body)
      if results['event_type'] == 'rights_transferred'
        acc['user_defined'] ||= {}
        acc['user_defined']['boolean_2'] = true
        changed = true
        deletes << event['ref']
        break
      end
    end


    # integer_1 > extent
    if acc.has_key?('user_defined')
      user_def = acc['user_defined']
      if user_def['integer_1']
        log "    found integer_1"
        log "      adding extent record"
        extent = {
          'portion' => 'part',
          'number' => user_def['integer_1'],
          'extent_type' => 'manuscript_items'
        }
        acc['extents'] << extent
        log "      removing integer_1"
        user_def.delete('integer_1')
        changed = true
      end
    end

    [changed, deletes]
  end


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


  def repo_for_code(repo_code)
    log "  finding repository for #{repo_code}"
    response = get_request("/search/repositories", {'page' => 1,'q' => "title='#{repo_code}'"})
    raise "Error: #{response.body}" unless response.code == '200'
    results = JSON.parse(response.body)
    log "    ... got #{results['results'].first['id']}"
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
    http = Net::HTTP.new(@backend_url.host, @backend_url.port)
    request = Net::HTTP::Delete.new(uri)
    request['X-ArchivesSpace-Session'] = @session
    http.request(request)
  end

end



options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: accession_fixes.rb [options]"

  opts.on('-b', '--backendurl URL', 'Backend URL') { |v| options[:backend_url] = v }
  opts.on('-u', '--username USERNAME', 'Username for backend session') { |v| options[:username] = v }
  opts.on('-p', '--password PASSWORD', 'Password for backend session') { |v| options[:password] = v }

  opts.on('--mssacode CODE', 'Repository code for MSSA') { |v| options[:mssa_code] = v }
  opts.on('--brblcode CODE', 'Repository code for BRBL') { |v| options[:brbl_code] = v }

  opts.on('-m', '--mssa', 'Run MSSA fixes') { |v| options[:fix_mssa] = v }
  opts.on('-b', '--brbl', 'Run BRBL fixes') { |v| options[:fix_brbl] = v }

  opts.on('-c', '--commit', 'Commit changes to the database') { |v| options[:commit] = v }

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
  fixer = AccessionFixer.new(options)
  fixer.fix_mssa(options[:mssa_code]) if options[:fix_mssa]
  fixer.fix_brbl(options[:brbl_code]) if options[:fix_brbl]
else
  puts "Nothing to do. Please specify -m, -b or both"
end
