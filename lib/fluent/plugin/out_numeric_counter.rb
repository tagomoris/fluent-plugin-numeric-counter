require 'fluent/plugin/output'
require 'pathname'

class Fluent::Plugin::NumericCounterOutput < Fluent::Plugin::Output
  Fluent::Plugin.register_output('numeric_counter', self)

  helpers :event_emitter, :storage, :timer

  DEFAULT_STORAGE_TYPE = 'local'
  PATTERN_MAX_NUM = 20

  config_param :count_interval, :time, default: 60,
               desc: 'The interval time to count in seconds.'
  config_param :unit, :enum, list: [:minute, :hour, :day], default: nil,
               desc: <<-DESC
The interval time to monitor specified an unit (either of minute, hour, or day).
Use either of count_interval or unit.
DESC
  config_param :output_per_tag, :bool, default: false,
               desc: 'Produce counter result per input tags.'

  config_param :aggregate, :enum, list: [:tag, :all], default: :tag,
               desc: 'Calculate in each input tag separetely, or all records in a mass.'
  config_param :tag, :string, default: 'numcount',
               desc: 'The output tag.'

  config_param :input_tag_remove_prefix, :string, default: nil,
               desc: 'The prefix string which will be removed from the input tag.'
  config_param :count_key, :string,
               desc: 'The key to count in the event record.'
  config_param :outcast_unmatched, :bool, default: false,
               desc: <<-DESC
Specify yes if you do not want to include 'unmatched' counts into percentage.
DESC
  config_param :output_messages, :bool, default: false,
               desc: 'Specify yes if you want to get tested messages.'

  config_param :store_file, :string, default: nil,
               obsoleted: 'Use store_storage parameter instead.',
               desc: 'Store internal data into a file of the given path on shutdown, and load on starting.'
  config_param :store_storage, :bool, default: false,
               desc: 'Store internal data into a storage on shutdown, and load on starting.'

  # pattern0 reserved as unmatched counts
  config_param :pattern1, :string,
               desc: <<-DESC
string: NAME LOW HIGH
LOW/HIGH allows size prefix (ex: 10k, 5M, 3500G)
Note that pattern0 reserved as unmatched counts.
DESC
  (2..PATTERN_MAX_NUM).each do |i|
    config_param ('pattern' + i.to_s).to_sym, :string, default: nil,
                 desc: 'string: NAME LOW HIGH'
  end

  config_param :tag_prefix, :string, default: nil,
               desc: 'The prefix string to be added to input tags. Use with "output_per_tag yes".',
               deprecated: 'Use @label routing instead.'

  config_section :storage do
    config_set_default :usage, 'resume'
    config_set_default :@type, DEFAULT_STORAGE_TYPE
  end

  attr_accessor :counts
  attr_accessor :last_checked
  attr_accessor :saved_duration
  attr_accessor :saved_at
  attr_accessor :patterns

  def parse_num(str)
    if str.nil?
      nil
    elsif str =~ /^[-0-9]+$/
      str.to_i
    elsif str =~ /^[-.0-9]+$/
      str.to_f
    else
      Fluent::Config.size_value(str)
    end
  end

  def configure(conf)
    label_routing_specified = conf.has_key?('@label')

    super

    if @unit
      @count_interval = case @unit
                        when :minute then 60
                        when :hour then 3600
                        when :day then 86400
                        else
                          raise "unknown unit:#{@unit}"
                        end
    end

    @patterns = [[0, 'unmatched', nil, nil]] # counts-index, name, low, high
    pattern_names = ['unmatched']

    invalids = conf.keys.select{|k| k =~ /^pattern(\d+)$/ and not (1..PATTERN_MAX_NUM).include?($1.to_i)}
    if invalids.size > 0
      log.warn "invalid number patterns (valid pattern number:1-#{PATTERN_MAX_NUM}):", invalids: invalids
    end
    (1..PATTERN_MAX_NUM).each do |i|
      next unless conf["pattern#{i}"]
      name,low,high = conf["pattern#{i}"].split(/ +/, 3)
      @patterns.push([i, name, parse_num(low), parse_num(high)])
      pattern_names.push(name)
    end
    pattern_index_list = conf.keys.select{|s| s =~ /^pattern\d$/}.map{|v| (/^pattern(\d)$/.match(v))[1].to_i}
    unless pattern_index_list.reduce(true){|v,i| v and @patterns[i]}
      raise Fluent::ConfigError, "jump of pattern index found"
    end
    unless @patterns.length == pattern_names.uniq.length
      raise Fluent::ConfigError, "duplicated pattern names found"
    end
    @patterns[1..-1].each do |index, name, low, high|
      raise Fluent::ConfigError, "numbers of low/high missing" if low.nil?
      raise Fluent::ConfigError, "unspecified high threshold allowed only in last pattern" if high.nil? and index != @patterns.length - 1
    end

    if @output_per_tag && (!label_routing_specified && !@tag_prefix)
      raise Fluent::ConfigError, "specify @label to route output events into other <label> sections."
    end
    if @output_per_tag && @tag_prefix
      @tag_prefix_string = @tag_prefix + '.'
    else
      @tag_prefix_string = nil
    end

    if @input_tag_remove_prefix
      @removed_prefix_string = @input_tag_remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end

    if @store_storage
      @storage = storage_create(usage: 'resume')
    end

    if system_config.workers > 1
      log.warn "Fluentd is now working with multi process workers, and numeric_counter plugin will produce counter results in each separeted processes."
    end

    @counts = count_initialized
    @mutex = Mutex.new
  end

  def multi_workers_ready?
    true
  end

  def start
    super

    load_status(@count_interval) if @store_storage

    @last_checked = Fluent::Engine.now

    timer_execute(:out_numeric_counter_timer, @count_interval) do
      now = Fluent::Engine.now
      flush_emit(now - @last_checked)
      @last_checked = now
    end
  end

  def shutdown
    save_status() if @store_storage
    super
  end

  def count_initialized(keys=nil)
    # counts['tag'][pattern_index_num] = count
    # counts['tag'][-1] = sum
    if @aggregate == :all
      {'all' => Array.new(@patterns.length + 1){|i| 0}}
    elsif keys
      values = Array.new(keys.length){|i|
        Array.new(@patterns.length + 1){|j| 0 }
      }
      Hash[[keys, values].transpose]
    else
      {}
    end
  end

  def countups(tag, counts)
    if @aggregate == :all
      tag = 'all'
    end

    @mutex.synchronize {
      @counts[tag] ||= [0] * (@patterns.length + 1)
      sum = 0
      counts.each_with_index do |count, i|
        sum += count
        @counts[tag][i] += count
      end
      @counts[tag][-1] += sum
    }
  end

  def stripped_tag(tag)
    return tag unless @input_tag_remove_prefix
    return tag[@removed_length..-1] if tag.start_with?(@removed_prefix_string) and tag.length > @removed_length
    return tag[@removed_length..-1] if tag == @input_tag_remove_prefix
    tag
  end

  def generate_fields(step, target_counts, attr_prefix, output)
    sum = if @outcast_unmatched
            target_counts[1..-2].inject(:+)
          else
            target_counts[-1]
          end
    messages = target_counts.delete_at(-1)

    target_counts.each_with_index do |count,i|
      name = @patterns[i][1]
      output[attr_prefix + name + '_count'] = count
      output[attr_prefix + name + '_rate'] = ((count * 100.0) / (1.00 * step)).floor / 100.0
      unless i == 0 and @outcast_unmatched
        output[attr_prefix + name + '_percentage'] = count * 100.0 / (1.00 * sum) if sum > 0
      end
      if @output_messages
        output[attr_prefix + 'messages'] = messages
      end
    end

    output
  end

  def generate_output(counts, step)
    if @aggregate == :all
      return generate_fields(step, counts['all'], '', {})
    end

    output = {}
    counts.keys.each do |tag|
      generate_fields(step, counts[tag], stripped_tag(tag) + '_', output)
    end
    output
  end

  def generate_output_per_tags(counts, step)
    if @aggregate == :all
      return {'all' => generate_fields(step, counts['all'], '', {})}
    end

    output_pairs = {}
    counts.keys.each do |tag|
      output_pairs[stripped_tag(tag)] = generate_fields(step, counts[tag], '', {})
    end
    output_pairs
  end

  def flush(step) # returns one message
    flushed,@counts = @counts,count_initialized(@counts.keys.dup.select{|k| @counts[k][-1] > 0})
    generate_output(flushed, step)
  end

  def flush_per_tags(step) # returns map of tag - message
    flushed,@counts = @counts,count_initialized(@counts.keys.dup.select{|k| @counts[k][-1] > 0})
    generate_output_per_tags(flushed, step)
  end

  def flush_emit(step)
    if @output_per_tag
      time = Fluent::Engine.now
      flush_per_tags(step).each do |tag,message|
        if @tag_prefix_string
          router.emit(@tag_prefix_string + tag, time, message)
        else
          router.emit(tag, time, message)
        end
      end
    else
      message = flush(step)
      if message.keys.size > 0
        router.emit(@tag, Fluent::Engine.now, message)
      end
    end
  end

  def process(tag, es)
    c = [0] * @patterns.length

    es.each do |time,record|
      value = record[@count_key]
      next if value.nil?

      value = value.to_f
      matched = false
      @patterns.each do |index, name, low, high|
        next if low.nil? or value < low or (not high.nil? and value >= high)
        c[index] += 1
        matched = true
        break
      end
      c[0] += 1 unless matched
    end
    countups(tag, c)
  end

  # Store internal status into a storage
  #
  def save_status()
    begin
      @saved_at = Fluent::Engine.now
      @saved_duration = @saved_at - @last_checked
      value = {
        "counts"         => @counts,
        "saved_at"       => @saved_at,
        "saved_duration" => @saved_duration,
        "aggregate"      => @aggregate.to_s,
        "count_key"      => @count_key,
        "patterns"       => @patterns,
      }
      @storage.put(:stored_value, value)
    rescue => e
      log.warn "Can't write store_storage", error: e
    end
  end

  # Load internal status from a storage
  #
  # @param [Interger] count_interval
  def load_status(count_interval)
    stored = @storage.get(:stored_value)
    return unless stored

    begin
      if stored["aggregate"] == @aggregate.to_s and
        stored["count_key"] == @count_key and
        stored["patterns"] == @patterns

        if Fluent::Engine.now <= stored["saved_at"] + count_interval
          @mutex.synchronize {
            @counts = stored["counts"]
            @saved_at = stored["saved_at"]
            @saved_duration = stored["saved_duration"]

            # skip the saved duration to continue counting
            @last_checked = Fluent::Engine.now - @saved_duration
          }
        else
          log.warn "stored data is outdated. ignore stored data"
        end
      else
        log.warn "configuration param was changed. ignore stored data"
      end
    rescue => e
      log.warn "Can't load store_storage", error: e
    end
  end

end
