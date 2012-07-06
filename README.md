# fluent-plugin-numeric-counter

## Component

### NumericCounterOutput

Fluentd plugin to count messages, matches for numeric range patterns, and emits its result (like fluent-plugin-datacounter).

- Counts per min/hour/day
- Counts per second (average every min/hour/day)
- Percentage of each numeric pattern in total counts of messages

NumericCounterOutput emits messages contains results data, so you can output these message (with 'numcount' tag by default) to any outputs you want.

    output ex1 (aggregates all inputs): {"pattern1_count":20, "pattern1_rate":0.333, "pattern1_percentage":25.0, "pattern2_count":40, "pattern2_rate":0.666, "pattern2_percentage":50.0, "unmatched_count":20, "unmatched_rate":0.333, "unmatched_percentage":25.0}
    output ex2 (aggregates per tag): {"test_pattern1_count":10, "test_pattern1_rate":0.333, "test_pattern1_percentage":25.0, "test_pattern2_count":40, "test_pattern2_rate":0.666, "test_pattern2_percentage":50.0, "test_unmatched_count":20, "test_unmatched_rate":0.333, "test_unmatched_percentage":25.0}

'input\_tag\_remove\_prefix' option available if you want to remove tag prefix from output field names.

If you want to omit 'unmatched' messages from percentage counting, specify 'outcast_unmatched yes'.

## Configuration

### NumericCounterOutput

Count messages that have attribute 'duration'(response time by microseconds), by several numeric ranges, per minutes.

    <match accesslog.**>
      type numeric_counter
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
      type numeric_counter
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

## TODO

* more tests
* more documents

## Copyright

* Copyright
  * Copyright (c) 2012- TAGOMORI Satoshi (tagomoris)
* License
  * Apache License, Version 2.0
