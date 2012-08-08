require 'helper'

class NumericCounterOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    count_interval 60
    aggregate tag
    input_tag_remove_prefix test
    count_key target
    pattern1 u100ms 0 100000
    pattern2 u1s 100000 1000000
    pattern3 u3s 1000000 3000000
  ]

  CONFIG_OUTPUT_PER_TAG = %[
    count_interval 60
    aggregate tag
    output_per_tag true
    tag_prefix n
    input_tag_remove_prefix test
    count_key target
    pattern1 u100ms 0 100000
    pattern2 u1s 100000 1000000
    pattern3 u3s 1000000 3000000
    output_messages true
  ]

  def create_driver(conf=CONFIG, tag='test')
    Fluent::Test::OutputTestDriver.new(Fluent::NumericCounterOutput, tag).configure(conf)
  end
  
  def test_parse_num
    p = create_driver.instance

    assert_equal 1, p.parse_num('1')
    assert_equal -1, p.parse_num('-1')
    assert_equal 1.0, p.parse_num('1.0')
    assert_equal -2.0, p.parse_num('-2.0000')
    assert_equal 1024, p.parse_num('1k')
  end

  def test_configure
    d = create_driver %[
      count_key field1
      pattern1 smallnum 0.1 200
      pattern2 subnum   -500 -1
    ]

    assert_equal 60, d.instance.count_interval
    assert_equal :tag, d.instance.aggregate
    assert_equal 'numcount', d.instance.tag
    assert_nil d.instance.input_tag_remove_prefix
    assert_equal false, d.instance.outcast_unmatched
    assert_equal [[0, 'unmatched', nil, nil], [1, 'smallnum', 0.1, 200], [2, 'subnum', -500, -1]], d.instance.patterns
    assert_equal false, d.instance.output_per_tag
    assert_equal false, d.instance.output_messages

    d = create_driver %[
      count_key key1
      pattern1 x 0.1 10
      pattern2 y 10 11
      pattern3 z 11
      output_messages yes
    ]
    assert_equal [[0, 'unmatched', nil, nil], [1, 'x', 0.1, 10], [2, 'y', 10, 11], [3, 'z', 11, nil]], d.instance.patterns
    assert_equal true, d.instance.output_messages
  end

  def test_configure_output_per_tag
    d = create_driver %[
      count_key field1
      pattern1 smallnum 0.1 200
      pattern2 subnum   -500 -1
      output_per_tag yes
      tag_prefix numcount
    ]

    assert_equal 60, d.instance.count_interval
    assert_equal :tag, d.instance.aggregate
    assert_equal 'numcount', d.instance.tag
    assert_nil d.instance.input_tag_remove_prefix
    assert_equal false, d.instance.outcast_unmatched
    assert_equal [[0, 'unmatched', nil, nil], [1, 'smallnum', 0.1, 200], [2, 'subnum', -500, -1]], d.instance.patterns
    assert_equal true, d.instance.output_per_tag
    assert_equal 'numcount', d.instance.tag_prefix
    assert_equal false, d.instance.output_messages

    d = create_driver %[
      count_key key1
      pattern1 x 0.1 10
      pattern2 y 10 11
      pattern3 z 11
      output_per_tag yes
      tag_prefix n
      output_messages yes
    ]
    assert_equal [[0, 'unmatched', nil, nil], [1, 'x', 0.1, 10], [2, 'y', 10, 11], [3, 'z', 11, nil]], d.instance.patterns
    assert_equal true, d.instance.output_per_tag
    assert_equal 'n', d.instance.tag_prefix
    assert_equal true, d.instance.output_messages

    x_config = %[
      count_key key1
      pattern1 x 0.1 10
      pattern2 y 10 11
      pattern3 z 11
      output_per_tag yes
    ]
    assert_raise(Fluent::ConfigError) {
      d = create_driver(x_config)
    }
  end

  def test_countups
    d = create_driver
    assert_nil d.instance.counts['test.input']

    d.instance.countups('test.input', [0, 0, 0, 0])
    assert_equal [0,0,0,0,0], d.instance.counts['test.input']
    d.instance.countups('test.input', [1, 1, 1, 0])
    assert_equal [1,1,1,0,3], d.instance.counts['test.input']
    d.instance.countups('test.input', [0, 5, 1, 0])
    assert_equal [1,6,2,0,9], d.instance.counts['test.input']
  end

  def test_generate_output
    d = create_driver
    # pattern1 u100ms 0 100000
    # pattern2 u1s 100000 1000000
    # pattern3 u3s 1000000 3000000

    r1 = d.instance.generate_output({'test.input' => [60,240,180,120,600], 'test.input2' => [0,600,0,0,600]}, 60)
    assert_equal   60, r1['input_unmatched_count']
    assert_equal  1.0, r1['input_unmatched_rate']
    assert_equal 10.0, r1['input_unmatched_percentage']
    assert_equal  240, r1['input_u100ms_count']
    assert_equal  4.0, r1['input_u100ms_rate']
    assert_equal 40.0, r1['input_u100ms_percentage']
    assert_equal  180, r1['input_u1s_count']
    assert_equal  3.0, r1['input_u1s_rate']
    assert_equal 30.0, r1['input_u1s_percentage']
    assert_equal  120, r1['input_u3s_count']
    assert_equal  2.0, r1['input_u3s_rate']
    assert_equal 20.0, r1['input_u3s_percentage']
    assert_nil r1['input_messages']

    assert_equal    0, r1['input2_unmatched_count']
    assert_equal  0.0, r1['input2_unmatched_rate']
    assert_equal  0.0, r1['input2_unmatched_percentage']
    assert_equal  600, r1['input2_u100ms_count']
    assert_equal 10.0, r1['input2_u100ms_rate']
    assert_equal 100.0, r1['input2_u100ms_percentage']
    assert_equal    0, r1['input2_u1s_count']
    assert_equal  0.0, r1['input2_u1s_rate']
    assert_equal  0.0, r1['input2_u1s_percentage']
    assert_equal    0, r1['input2_u3s_count']
    assert_equal  0.0, r1['input2_u3s_rate']
    assert_equal  0.0, r1['input2_u3s_percentage']
    assert_nil r1['input2_messages']

    d = create_driver(CONFIG + "\n output_messages yes \n")

    r1 = d.instance.generate_output({'test.input' => [60,240,180,120,600], 'test.input2' => [0,600,0,0,600]}, 60)
    assert_equal 600, r1['input_messages']
    assert_equal 600, r1['input2_messages']

    d = create_driver %[
      aggregate all
      count_key f1
      pattern1 good 1 2
      outcast_unmatched yes
      output_messages true
    ]
    r2 = d.instance.generate_output({'all' => [60,240,300]}, 60)
    assert_equal  60, r2['unmatched_count']
    assert_equal 1.0, r2['unmatched_rate']
    assert_nil r2['unmatched_percentage']
    assert_equal 240, r2['good_count']
    assert_equal 4.0, r2['good_rate']
    assert_equal 100.0, r2['good_percentage']
    assert_equal 300, r2['messages']
  end

  def test_generate_output_per_tag
    d = create_driver(CONFIG_OUTPUT_PER_TAG + "\n output_messages false \n")
    # pattern1 u100ms 0 100000
    # pattern2 u1s 100000 1000000
    # pattern3 u3s 1000000 3000000

    r1 = d.instance.generate_output_per_tags({'test.input' => [60,240,180,120,600], 'test.input2' => [0,600,0,0,600]}, 60)
    assert_equal 2, r1.keys.size

    r = r1['input']
    assert_equal   60, r['unmatched_count']
    assert_equal  1.0, r['unmatched_rate']
    assert_equal 10.0, r['unmatched_percentage']
    assert_equal  240, r['u100ms_count']
    assert_equal  4.0, r['u100ms_rate']
    assert_equal 40.0, r['u100ms_percentage']
    assert_equal  180, r['u1s_count']
    assert_equal  3.0, r['u1s_rate']
    assert_equal 30.0, r['u1s_percentage']
    assert_equal  120, r['u3s_count']
    assert_equal  2.0, r['u3s_rate']
    assert_equal 20.0, r['u3s_percentage']
    assert_nil r['messages']

    r = r1['input2']
    assert_equal    0, r['unmatched_count']
    assert_equal  0.0, r['unmatched_rate']
    assert_equal  0.0, r['unmatched_percentage']
    assert_equal  600, r['u100ms_count']
    assert_equal 10.0, r['u100ms_rate']
    assert_equal 100.0, r['u100ms_percentage']
    assert_equal    0, r['u1s_count']
    assert_equal  0.0, r['u1s_rate']
    assert_equal  0.0, r['u1s_percentage']
    assert_equal    0, r['u3s_count']
    assert_equal  0.0, r['u3s_rate']
    assert_equal  0.0, r['u3s_percentage']
    assert_nil r['messages']

    d = create_driver(CONFIG_OUTPUT_PER_TAG)

    r1 = d.instance.generate_output_per_tags({'test.input' => [60,240,180,120,600], 'test.input2' => [0,600,0,0,600]}, 60)
    assert_equal 600, r1['input']['messages']
    assert_equal 600, r1['input2']['messages']

    d = create_driver %[
      aggregate all
      count_key f1
      pattern1 good 1 2
      outcast_unmatched yes
      output_messages true
    ]
    r2 = d.instance.generate_output_per_tags({'all' => [60,240,300]}, 60)
    assert_equal  60, r2['all']['unmatched_count']
    assert_equal 1.0, r2['all']['unmatched_rate']
    assert_nil r2['all']['unmatched_percentage']
    assert_equal 240, r2['all']['good_count']
    assert_equal 4.0, r2['all']['good_rate']
    assert_equal 100.0, r2['all']['good_percentage']
    assert_equal 300, r2['all']['messages']
  end

  def test_pattern_num
    assert_equal 20, Fluent::NumericCounterOutput::PATTERN_MAX_NUM

    conf = %[
      aggregate all
      count_key field
    ]
    (1..20).each do |i|
      conf += "pattern#{i} name#{i} #{i} #{i+1}\n"
    end
    d = create_driver(conf, 'test.max')
    d.run do
      (0..21).each do |i|
        d.emit({'field' => i})
      end
    end
    r = d.instance.flush(60)
    assert_equal 2, r['unmatched_count'] # 0 and 21
    assert_equal 1, r['name1_count']
    assert_equal 1, r['name2_count']
    assert_equal 1, r['name3_count']
    assert_equal 1, r['name4_count']
    assert_equal 1, r['name5_count']
    assert_equal 1, r['name6_count']
    assert_equal 1, r['name7_count']
    assert_equal 1, r['name8_count']
    assert_equal 1, r['name9_count']
    assert_equal 1, r['name10_count']
    assert_equal 1, r['name11_count']
    assert_equal 1, r['name12_count']
    assert_equal 1, r['name13_count']
    assert_equal 1, r['name14_count']
    assert_equal 1, r['name15_count']
    assert_equal 1, r['name16_count']
    assert_equal 1, r['name17_count']
    assert_equal 1, r['name18_count']
    assert_equal 1, r['name19_count']
    assert_equal 1, r['name20_count']
  end

  def test_emit
  # CONFIG = %[
  #   count_interval 60
  #   aggregate tag
  #   input_tag_remove_prefix test
  #   count_key target
  #   pattern1 u100ms 0 100000
  #   pattern2 u1s 100000 1000000
  #   pattern3 u3s 1000000 3000000
  # ]
    d = create_driver(CONFIG, 'test.tag1')
    d.run do
      60.times do
        d.emit({'target' =>  '50000'})
        d.emit({'target' => '100000'})
        d.emit({'target' => '100001'})
        d.emit({'target' => '0.0'})
        d.emit({'target' => '-1'})
      end
    end
    r = d.instance.flush(60)

    assert_equal 120, r['tag1_u100ms_count']
    assert_equal 2.0, r['tag1_u100ms_rate']
    assert_equal 40.0, r['tag1_u100ms_percentage']
    assert_equal 120, r['tag1_u1s_count']
    assert_equal 2.0, r['tag1_u1s_rate']
    assert_equal 40, r['tag1_u1s_percentage']
    assert_equal 0, r['tag1_u3s_count']
    assert_equal 0, r['tag1_u3s_rate']
    assert_equal 0, r['tag1_u3s_percentage']
    assert_equal 60, r['tag1_unmatched_count']
    assert_equal 1.0, r['tag1_unmatched_rate']
    assert_equal 20, r['tag1_unmatched_percentage']

    d = create_driver(CONFIG, 'test.tag1')
    d.run do
      60.times do
        d.emit({'target' =>  '50000'})
        d.emit({'target' => '100000'})
        d.emit({'target' => '100001'})
        d.emit({'target' => '0.0'})
        d.emit({'target' => '-1'})
      end
    end
    d.instance.flush_emit(60)
    emits = d.emits
    assert_equal 1, emits.length
    data = emits[0]
    assert_equal 'numcount', data[0] # tag
    r = data[2] # message
    assert_equal 120, r['tag1_u100ms_count']
    assert_equal 2.0, r['tag1_u100ms_rate']
    assert_equal 40.0, r['tag1_u100ms_percentage']
    assert_equal 120, r['tag1_u1s_count']
    assert_equal 2.0, r['tag1_u1s_rate']
    assert_equal 40, r['tag1_u1s_percentage']
    assert_equal 0, r['tag1_u3s_count']
    assert_equal 0, r['tag1_u3s_rate']
    assert_equal 0, r['tag1_u3s_percentage']
    assert_equal 60, r['tag1_unmatched_count']
    assert_equal 1.0, r['tag1_unmatched_rate']
    assert_equal 20, r['tag1_unmatched_percentage']
  end

  def test_emit_output_per_tag
    d = create_driver(CONFIG_OUTPUT_PER_TAG, 'test.tag1')
    d.run do
      60.times do
        d.emit({'target' =>  '50000'})
        d.emit({'target' => '100000'})
        d.emit({'target' => '100001'})
        d.emit({'target' => '0.0'})
        d.emit({'target' => '-1'})
      end
    end
    r = d.instance.flush_per_tags(60)
    assert_equal 1, r.keys.size
    r1 = r['tag1']
    assert_equal 120, r1['u100ms_count']
    assert_equal 2.0, r1['u100ms_rate']
    assert_equal 40.0, r1['u100ms_percentage']
    assert_equal 120, r1['u1s_count']
    assert_equal 2.0, r1['u1s_rate']
    assert_equal 40, r1['u1s_percentage']
    assert_equal 0, r1['u3s_count']
    assert_equal 0, r1['u3s_rate']
    assert_equal 0, r1['u3s_percentage']
    assert_equal 60, r1['unmatched_count']
    assert_equal 1.0, r1['unmatched_rate']
    assert_equal 20, r1['unmatched_percentage']
    assert_equal 300, r1['messages']

    d = create_driver(CONFIG_OUTPUT_PER_TAG, 'test.tag1')
    d.run do
      60.times do
        d.emit({'target' =>  '50000'})
        d.emit({'target' => '100000'})
        d.emit({'target' => '100001'})
        d.emit({'target' => '0.0'})
        d.emit({'target' => '-1'})
      end
    end
    d.instance.flush_emit(60)
    emits = d.emits
    assert_equal 1, emits.length
    data = emits[0]
    assert_equal 'n.tag1', data[0] # tag
    r = data[2] # message
    assert_equal 120, r['u100ms_count']
    assert_equal 2.0, r['u100ms_rate']
    assert_equal 40.0, r['u100ms_percentage']
    assert_equal 120, r['u1s_count']
    assert_equal 2.0, r['u1s_rate']
    assert_equal 40, r['u1s_percentage']
    assert_equal 0, r['u3s_count']
    assert_equal 0, r['u3s_rate']
    assert_equal 0, r['u3s_percentage']
    assert_equal 60, r['unmatched_count']
    assert_equal 1.0, r['unmatched_rate']
    assert_equal 20, r['unmatched_percentage']
    assert_equal 300, r['messages']
  end

  def test_zero_tags
    fields = ['unmatched','u100ms','u1s','u3s'].map{|k| 'tag1_' + k}.map{|p|
      ['count', 'rate', 'percentage'].map{|a| p + '_' + a}
    }.flatten
    fields_without_percentage = ['unmatched','u100ms','u1s','u3s'].map{|k| 'tag1_' + k}.map{|p|
      ['count', 'rate'].map{|a| p + '_' + a}
    }.flatten

    d = create_driver(CONFIG, 'test.tag1')
    # CONFIG = %[
    #   count_interval 60
    #   aggregate tag
    #   input_tag_remove_prefix test
    #   count_key target
    #   pattern1 u100ms 0 100000
    #   pattern2 u1s 100000 1000000
    #   pattern3 u3s 1000000 3000000
    # ]
    d.run do
      60.times do
        d.emit({'target' =>  '50000'})
        d.emit({'target' => '100000'})
        d.emit({'target' => '100001'})
        d.emit({'target' => '0.0'})
        d.emit({'target' => '-1'})
      end
    end
    d.instance.flush_emit(60)
    assert_equal 1, d.emits.size
    r1 = d.emits[0][2]
    assert_equal fields, r1.keys

    d.instance.flush_emit(60)
    assert_equal 2, d.emits.size # +1
    r2 = d.emits[1][2]
    assert_equal fields_without_percentage, r2.keys
    assert_equal [0]*8, r2.values

    d.instance.flush_emit(60)
    assert_equal 2, d.emits.size # +0
  end

  def test_zero_tags_per_tag
    fields = (['unmatched','u100ms','u1s','u3s'].map{|p|
        ['count', 'rate', 'percentage'].map{|a| p + '_' + a}
      }.flatten + ['messages']).sort
    fields_without_percentage = (['unmatched','u100ms','u1s','u3s'].map{|p|
        ['count', 'rate'].map{|a| p + '_' + a}
      }.flatten + ['messages']).sort

    d = create_driver(CONFIG_OUTPUT_PER_TAG, 'test.tag1')
    # CONFIG_OUTPUT_PER_TAG = %[
    #   count_interval 60
    #   aggregate tag
    #   output_per_tag true
    #   tag_prefix n
    #   input_tag_remove_prefix test
    #   count_key target
    #   pattern1 u100ms 0 100000
    #   pattern2 u1s 100000 1000000
    #   pattern3 u3s 1000000 3000000
    #   output_messages true
    # ]
    d.run do
      60.times do
        d.emit({'target' =>  '50000'})
        d.emit({'target' => '100000'})
        d.emit({'target' => '100001'})
        d.emit({'target' => '0.0'})
        d.emit({'target' => '-1'})
      end
    end
    d.instance.flush_emit(60)
    assert_equal 1, d.emits.size
    r1 = d.emits[0][2]
    assert_equal fields, r1.keys.sort

    d.instance.flush_emit(60)
    assert_equal 2, d.emits.size # +1
    r2 = d.emits[1][2]
    assert_equal fields_without_percentage, r2.keys.sort
    assert_equal [0]*9, r2.values # (_count, _rate) x4 + messages

    d.instance.flush_emit(60)
    assert_equal 2, d.emits.size # +0
  end
end
