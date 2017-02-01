# fluent-plugin-numeric-counter

[Fluentd](http://fluentd.org) plugin to count messages, matches for numeric range patterns, and emits its result (like fluent-plugin-datacounter).

- Counts per min/hour/day
- Counts per second (average every min/hour/day)
- Percentage of each numeric pattern in total counts of messages

NumericCounterOutput emits messages contains results data, so you can output these message (with 'numcount' tag by default) to any outputs you want.

    output ex1 (aggregates all inputs): {"pattern1_count":20, "pattern1_rate":0.333, "pattern1_percentage":25.0, "pattern2_count":40, "pattern2_rate":0.666, "pattern2_percentage":50.0, "unmatched_count":20, "unmatched_rate":0.333, "unmatched_percentage":25.0}
    output ex2 (aggregates per tag): {"test_pattern1_count":10, "test_pattern1_rate":0.333, "test_pattern1_percentage":25.0, "test_pattern2_count":40, "test_pattern2_rate":0.666, "test_pattern2_percentage":50.0, "test_unmatched_count":20, "test_unmatched_rate":0.333, "test_unmatched_percentage":25.0}

`input_tag_remove_prefix` option available if you want to remove tag prefix from output field names.

If you want to omit 'unmatched' messages from percentage counting, specify 'outcast_unmatched yes'.

## Configuration

### NumericCounterOutput

Count messages that have attribute 'duration'(response time by microseconds), by several numeric ranges, per minutes.

    <match accesslog.**>
      @type numeric_counter
      unit minute           # or 'count_interval 60s' or '45s', '3m' ... as you want
      aggregate all         # or 'tag'
      count_key duration

      # patternX: X(1-20)
      # patternX NAME LOW HIGH  #=> patternX matches N like LOW <= N < HIGH

      pattern1 HIGHSPEED            0 10000 # under 10ms
      pattern2 SEMIHIGHSPEED   10000 100000 # under 100ms
      pattern3 NORMAL        100000 1000000 # under 1s
      pattern4 STUPID       1000000 10000000 # under 10s!
      
      # patternZ (Z is last number of specified patterns)
      # patternZ NAME LOW  #=> patternZ matches N like LOW <= N (upper threshold is unlimited)
      patternZ MUSTDIE     10000000  # over 10s!
    </match>

Size specifier (like 10k, 5M, 103g) available as 1024\*\*1, 1024\*\*2, 1024\*\*3 ...., for example, for bytes of access log.

    <match accesslog.**>
      @type numeric_counter
      unit hour
      aggregate tag
      count_key bytes
      
      pattern1 SMALL    0 1k
      pattern2 MIDDLE  1k 1m
      pattern3 LARGE   1m 10m
      pattern4 HUGE   10m 1g
      pattern5 XXXX    1g
    </match>

You can try to use negative numbers, and floating point numbers.... (not tested enough).

With 'output\_per\_tag' option and '@label', we get one result message for one tag, routed to specified label:

    <match accesslog.{foo,bar}>
      @type numeric_counter
      @label @log_count
      unit hour
      aggregate tag
      count_key bytes
      output_per_tag yes
      input_tag_remove_prefix accesslog
      
      pattern1 SMALL    0 1k
      pattern2 MIDDLE  1k 1m
      pattern3 LARGE   1m 10m
      pattern4 HUGE   10m 1g
      pattern5 XXXX    1g
    </match>
    
    <label @log_count>
      <match foo>
        # => tag: 'foo'
        #    message: {'SMALL_count' => 100, ... }
      </match>
      <match bar>
        # => tag: 'bar'
        #    message: {'SMALL_count' => 100, ... }
      </match>
    </label>

And you can get tested messages count with 'output\_messages' option:

    <match accesslog.{foo,bar}>
      @type numeric_counter
      unit hour
      aggregate tag
      count_key bytes
      input_tag_remove_prefix accesslog
      output_messages yes
      
      pattern1 SMALL    0 1k
      pattern2 LARGE   1k
    </match>
    # => tag: 'numcount'
    #    message: {'foo_messages' => xxx, 'bar_messages' => yyy, 'foo_SMALL_count' => 100, ... }
    
    <match accesslog.{foo,bar}>
      @type numeric_counter
      unit hour
      aggregate tag
      count_key bytes
      output_per_tag yes
      tag_prefix num
      input_tag_remove_prefix accesslog
      output_messages yes
      
      pattern1 SMALL    0 1k
      pattern2 LARGE   1k
    </match>
    # => tag: 'num.foo' or 'num.bar'
    #    message: {'messages' => xxx, 'SMALL_count' => 100, ... }

## Parameters

* count\_key (required)

    The key to count in the event record.

* tag

    The output tag. Default is `numcount`.

* tag\_prefix

    The prefix string which will be added to the input tag. `output_per_tag yes` must be specified together. 

* input\_tag\_remove\_prefix

    The prefix string which will be removed from the input tag.

* count\_interval

    The interval time to count in seconds. Default is `60`.

* unit

    The interval time to monitor specified an unit (either of `minute`, `hour`, or `day`).
    Use either of `count_interval` or `unit`.

* aggregate

    Calculate in each input `tag` separetely, or `all` records in a mass. Default is `tag`.

* ouput\_per\_tag

    Emit for each input tag. `tag_prefix` must be specified together. Default is `no`.

* outcast\_unmatched

    Specify `yes` if you do not want to include 'unmatched' counts into percentage. Default is `no`.

* output\_messages

    Specify `yes` if you want to get tested messages. Default is `no`.

* store\_file

    Store internal data into a file of the given path on shutdown, and load on starting.

## TODO

* more tests
* more documents

## Copyright

* Copyright
  * Copyright (c) 2012- TAGOMORI Satoshi (tagomoris)
* License
  * Apache License, Version 2.0
