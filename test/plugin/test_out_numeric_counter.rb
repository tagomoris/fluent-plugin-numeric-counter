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

    d = create_driver %[
      count_key key1
      pattern1 x 0.1 10
      pattern2 y 10 11
      pattern3 z 11
    ]
    assert_equal [[0, 'unmatched', nil, nil], [1, 'x', 0.1, 10], [2, 'y', 10, 11], [3, 'z', 11, nil]], d.instance.patterns
  end

  def test_countups
    d = create_driver
    assert_nil d.instance.counts['test.input']

    d.instance.countups('test.input', [0, 0, 0, 0])
    assert_equal [0,0,0,0], d.instance.counts['test.input']
    d.instance.countups('test.input', [1, 1, 1, 0])
    assert_equal [1,1,1,0], d.instance.counts['test.input']
    d.instance.countups('test.input', [0, 5, 1, 0])
    assert_equal [1,6,2,0], d.instance.counts['test.input']
  end

  def test_generate_output
    d = create_driver
    # pattern1 u100ms 0 100000
    # pattern2 u1s 100000 1000000
    # pattern3 u3s 1000000 3000000

    r1 = d.instance.generate_output({'test.input' => [60,240,180,120], 'test.input2' => [0,600,0,0]}, 60)
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

    d = create_driver %[
      aggregate all
      count_key f1
      pattern1 good 1 2
      outcast_unmatched yes
    ]
    r2 = d.instance.generate_output({'all' => [60,240]}, 60)
    assert_equal  60, r2['unmatched_count']
    assert_equal 1.0, r2['unmatched_rate']
    assert_nil r2['unmatched_percentage']
    assert_equal 240, r2['good_count']
    assert_equal 4.0, r2['good_rate']
    assert_equal 100.0, r2['good_percentage']
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
  end
end
