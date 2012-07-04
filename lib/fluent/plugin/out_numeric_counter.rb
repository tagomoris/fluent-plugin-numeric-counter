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
  config_param :pattern1, :string # string: NAME LOW-HIGH
  (2..PATTERN_MAX_NUM).each do |i|
    config_param ('pattern' + i.to_s).to_sym, :string, :default => nil
  end
  
  attr_accessor :tick, :counts, :last_checked

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

    @patterns = []
    #TODO ato de kaku

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
    #TODO ato de kaku
  end

  def countups(tag, counts)
    #TODO ato de kaku
  end

  def stripped_tag(tag)
    #TODO ato de kaku
  end

  def generate_output(counts, step)
    #TODO ato de kaku
  end

  def flush(step)
    #TODO
  end

  def flush_emit(step)
    #TODO
  end

  def start_watch
    #TODO
  end

  def watch
    #TODO
  end

  def emit(tag, es, chain)
    #TODO
  end
end
