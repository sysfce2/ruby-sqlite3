require 'helper'
require 'iconv'

module SQLite3
  class TestDatabase < Test::Unit::TestCase
    def setup
      @db = SQLite3::Database.new(':memory:')
    end

    def test_new
      db = SQLite3::Database.new(':memory:')
      assert db
    end

    def test_new_yields_self
      thing = nil
      SQLite3::Database.new(':memory:') do |db|
        thing = db
      end
      assert_instance_of(SQLite3::Database, thing)
    end

    def test_new_with_options
      db = SQLite3::Database.new(Iconv.conv('UTF-16LE', 'UTF-8', ':memory:'),
                                 :utf16 => true)
      assert db
    end

    def test_close
      db = SQLite3::Database.new(':memory:')
      db.close
      assert db.closed?
    end

    def test_block_closes_self
      thing = nil
      SQLite3::Database.new(':memory:') do |db|
        thing = db
        assert !thing.closed?
      end
      assert thing.closed?
    end

    def test_prepare
      db = SQLite3::Database.new(':memory:')
      stmt = db.prepare('select "hello world"')
      assert_instance_of(SQLite3::Statement, stmt)
    end

    def test_total_changes
      db = SQLite3::Database.new(':memory:')
      db.execute("create table foo ( a integer primary key, b text )")
      db.execute("insert into foo (b) values ('hello')")
      assert_equal 1, db.total_changes
    end

    def test_execute_returns_list_of_hash
      db = SQLite3::Database.new(':memory:', :results_as_hash => true)
      db.execute("create table foo ( a integer primary key, b text )")
      db.execute("insert into foo (b) values ('hello')")
      rows = db.execute("select * from foo")
      assert_equal [{"a"=>1, "b"=>"hello"}], rows
    end

    def test_total_changes_closed
      db = SQLite3::Database.new(':memory:')
      db.close
      assert_raise(SQLite3::Exception) do
        db.total_changes
      end
    end

    def test_trace_requires_opendb
      @db.close
      assert_raise(SQLite3::Exception) do
        @db.trace { |x| }
      end
    end

    def test_trace_with_block
      result = nil
      @db.trace { |sql| result = sql }
      @db.execute "select 'foo'"
      assert_equal "select 'foo'", result
    end

    def test_trace_with_object
      obj = Class.new {
        attr_accessor :result
        def call sql; @result = sql end
      }.new

      @db.trace(obj)
      @db.execute "select 'foo'"
      assert_equal "select 'foo'", obj.result
    end

    def test_trace_takes_nil
      @db.trace(nil)
      @db.execute "select 'foo'"
    end

    def test_last_insert_row_id_closed
      @db.close
      assert_raise(SQLite3::Exception) do
        @db.last_insert_row_id
      end
    end

    def test_define_function
      called_with = nil
      @db.define_function("hello") do |value|
        called_with = value
      end
      @db.execute("select hello(10)")
      assert_equal 10, called_with
    end

    def test_call_func_arg_type
      called_with = nil
      @db.define_function("hello") do |b, c, d|
        called_with = [b, c, d]
        nil
      end
      @db.execute("select hello(2.2, 'foo', NULL)")
      assert_equal [2.2, 'foo', nil], called_with
    end

    def test_define_varargs
      called_with = nil
      @db.define_function("hello") do |*args|
        called_with = args
        nil
      end
      @db.execute("select hello(2.2, 'foo', NULL)")
      assert_equal [2.2, 'foo', nil], called_with
    end

    def test_function_return
      @db.define_function("hello") { |a| 10 }
      assert_equal [10], @db.execute("select hello('world')").first
    end

    def test_function_return_types
      [10, 2.2, nil, "foo"].each do |thing|
        @db.define_function("hello") { |a| thing }
        assert_equal [thing], @db.execute("select hello('world')").first
      end
    end

    def test_define_function_closed
      @db.close
      assert_raise(SQLite3::Exception) do
        @db.define_function('foo') {  }
      end
    end

    def test_inerrupt_closed
      @db.close
      assert_raise(SQLite3::Exception) do
        @db.interrupt
      end
    end

    def test_define_aggregate
      @db.execute "create table foo ( a integer primary key, b text )"
      @db.execute "insert into foo ( b ) values ( 'foo' )"
      @db.execute "insert into foo ( b ) values ( 'bar' )"
      @db.execute "insert into foo ( b ) values ( 'baz' )"

      acc = Class.new {
        attr_reader :sum
        alias :finalize :sum
        def initialize
          @sum = 0
        end

        def step a
          @sum += a
        end
      }.new

      @db.define_aggregator("accumulate", acc)
      value = @db.get_first_value( "select accumulate(a) from foo" )
      assert_equal 6, value
    end

    def test_authorizer_ok
      @db.authorizer = Class.new {
        def call action, a, b, c, d; true end
      }.new
      @db.prepare("select 'fooooo'")

      @db.authorizer = Class.new {
        def call action, a, b, c, d; 0 end
      }.new
      @db.prepare("select 'fooooo'")
    end

    def test_authorizer_ignore
      @db.authorizer = Class.new {
        def call action, a, b, c, d; nil end
      }.new
      stmt = @db.prepare("select 'fooooo'")
      assert_equal nil, stmt.step
    end

    def test_authorizer_fail
      @db.authorizer = Class.new {
        def call action, a, b, c, d; false end
      }.new
      assert_raises(SQLite3::AuthorizationException) do
        @db.prepare("select 'fooooo'")
      end
    end

    def test_remove_auth
      @db.authorizer = Class.new {
        def call action, a, b, c, d; false end
      }.new
      assert_raises(SQLite3::AuthorizationException) do
        @db.prepare("select 'fooooo'")
      end

      @db.authorizer = nil
      @db.prepare("select 'fooooo'")
    end

    def test_close_with_open_statements
      stmt = @db.prepare("select 'foo'")
      assert_raises(SQLite3::BusyException) do
        @db.close
      end
    end
  end
end
