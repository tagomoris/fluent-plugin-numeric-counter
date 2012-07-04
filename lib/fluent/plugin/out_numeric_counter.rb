class Fluent::NumericCounterOutput < Fluent::Output
  Fluent::Plugin.register_output('numeric_counter', self)

  PATTERN_MAX_NUM = 20

  config_param :count_interval, :time, :default => 60
  config_param :unit, :string, :default => nil
  config_param :aggregate, :string, :default => 'tag'
  config_param :tag, :string, :default => 'numcount'
  config_param :input_tag_remove_prefix, :string, :default => nil
  config_param :count_key, :string
  config_param :outcast_unmatched, :bool, :default => false

  # pattern0 reserved as unmatched counts
  config_param :pattern1, :string # string: NAME LOW HIGH
                                  # LOW/HIGH allows size prefix (ex: 10k, 5M, 3500G)
  (2..PATTERN_MAX_NUM).each do |i|
    config_param ('pattern' + i.to_s).to_sym, :string, :default => nil
  end
  
  attr_accessor :counts, :last_checked

  # for test
  # attr_accessor :count_interval, :unit, :aggregate, :tag, :input_tag_remove_prefix, :count_key, :outcast_unmatched
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
    super

    if @unit
      @count_interval = case @unit
                        when 'minute' then 60
                        when 'hour' then 3600
                        when 'day' then 86400
                        else
                          raise Fluent::ConfigError, 'unit must be one of minute/hour/day'
                        end
    end

    @aggregate = @aggregate.to_sym
    raise Fluent::ConfigError, "numeric_counter allows tag/all to aggregate unit" unless [:tag, :all].include?(@aggregate)

    @patterns = [[0, 'unmatched', nil, nil]] # counts-index, name, low, high
    pattern_names = ['unmatched']

    invalids = conf.keys.select{|k| k =~ /^pattern(\d+)$/ and not (1..PATTERN_MAX_NUM).include?($1.to_i)}
    if invalids.size > 0
      $log.warn "invalid number patterns (valid pattern number:1-#{PATTERN_MAX_NUM}):" + invalids.join(",")
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
    
    if @input_tag_remove_prefix
      @removed_prefix_string = @input_tag_remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end

    @counts = count_initialized
    @mutex = Mutex.new
  end

  def start
    super
    start_watch
  end

  def shutdown
    super
    @watcher.terminate
    @watcher.join
  end

  def count_initialized(keys=nil)
    # counts['tag'][pattern_index_num] = count
    if @aggregate == :all
      {'all' => Array.new(@patterns.length){|i| 0}}
    elsif keys
      values = Array.new(keys.length){|i|
        Array.new(@patterns.length){|j| 0 }
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
      @counts[tag] ||= [0] * @patterns.length
      counts.each_with_index do |count, i|
        @counts[tag][i] += count
      end
    }
  end

  def stripped_tag(tag)
    return tag unless @input_tag_remove_prefix
    return tag[@removed_length..-1] if tag.start_with?(@removed_prefix_string) and tag.length > @removed_length
    return tag[@removed_length..-1] if tag == @input_tag_remove_prefix
    tag
  end

  def generate_output(counts, step)
    output = {}

    if @aggregate == :all
      # index 0 is unmatched
      sum = if @outcast_unmatched
              counts['all'][1..-1].inject(:+)
            else
              counts['all'].inject(:+)
            end
      counts['all'].each_with_index do |count,i|
        name = @patterns[i][1]
        output[name + '_count'] = count
        output[name + '_rate'] = ((count * 100.0) / (1.00 * step)).floor / 100.0
        unless i == 0 and @outcast_unmatched
          output[name + '_percentage'] = count * 100.0 / (1.00 * sum) if sum > 0
        end
      end
      return output
    end

    counts.keys.each do |tag|
      t = stripped_tag(tag)
      sum = if @outcast_unmatched
              counts[tag][1..-1].inject(:+)
            else
              counts[tag].inject(:+)
            end
      counts[tag].each_with_index do |count,i|
        name = @patterns[i][1]
        output[t + '_' + name + '_count'] = count
        output[t + '_' + name + '_rate'] = ((count * 100.0) / (1.00 * step)).floor / 100.0
        unless i == 0 and @outcast_unmatched
          output[t + '_' + name + '_percentage'] = count * 100.0 / (1.00 * sum) if sum > 0
        end
      end
    end
    output
  end

  def flush(step)
    flushed,@counts = @counts,count_initialized(@counts.keys.dup)
    generate_output(flushed, step)
  end

  def flush_emit(step)
    Fluent::Engine.emit(@tag, Fluent::Engine.now, flush(step))
  end

  def start_watch
    @watcher = Thread.new(&method(:watch))
  end

  def watch
    @last_checked = Fluent::Engine.now
    while true
      sleep 0.5
      if Fluent::Engine.now - @last_checked >= @count_interval
        now = Fluent::Engine.now
        flush_emit(now - @last_checked)
        @last_checked = now
      end
    end
  end

  def emit(tag, es, chain)
    c = [0] * @patterns.length

    es.each do |time,record|
      value = record[@count_key]
      next if value.nil?

      value = value.to_f
      matched = false
      @patterns.each do |index, name, low, high|
        next if low.nil? or value < low or value >= high
        c[index] += 1
        matched = true
        break
      end
      c[0] += 1 unless matched
    end
    countups(tag, c)

    chain.next
  end
end
