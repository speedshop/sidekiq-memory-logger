# frozen_string_literal: true

require "test_helper"

class TestSidekiqMemoryLoggerMiddleware < Minitest::Test
  def setup
    @job = {"class" => "TestJob"}
    @queue = "test_queue"
    # Reset configuration first
    Sidekiq::MemoryLogger.configuration.callback = nil
    Sidekiq::MemoryLogger.configuration.logger = nil
    # Create middleware after resetting config so it gets clean config
    @middleware = Sidekiq::MemoryLogger::Middleware.new
  end

  def test_middleware_calls_callback_when_configured
    callback_calls = []

    Sidekiq::MemoryLogger.configure do |config|
      config.callback = ->(job_class, queue, memory_diff) do
        callback_calls << [job_class, queue, memory_diff]
      end
    end

    # Create new middleware after configuration change
    middleware = Sidekiq::MemoryLogger::Middleware.new
    middleware.call(nil, @job, @queue) { sleep 0.01 }

    assert_equal 1, callback_calls.length
    job_class, queue, memory_diff = callback_calls.first
    assert_equal "TestJob", job_class
    assert_equal "test_queue", queue
    assert_kind_of Float, memory_diff
  end

  def test_middleware_logs_when_no_callback
    log_output = StringIO.new
    test_logger = Logger.new(log_output)

    Sidekiq::MemoryLogger.configure do |config|
      config.logger = test_logger
    end

    # Create new middleware after configuration change
    middleware = Sidekiq::MemoryLogger::Middleware.new
    middleware.call(nil, @job, @queue) { sleep 0.01 }

    log_content = log_output.string
    assert_includes log_content, "Job TestJob on queue test_queue used"
    assert_includes log_content, "MB"
  end

  def test_middleware_handles_exceptions
    callback_calls = []

    Sidekiq::MemoryLogger.configure do |config|
      config.callback = ->(job_class, queue, memory_diff) do
        callback_calls << [job_class, queue, memory_diff]
      end
    end

    # Create new middleware after configuration change
    middleware = Sidekiq::MemoryLogger::Middleware.new

    assert_raises(RuntimeError) do
      middleware.call(nil, @job, @queue) { raise "test error" }
    end

    assert_equal 1, callback_calls.length
  end

  def test_middleware_handles_callback_exceptions
    log_output = StringIO.new
    test_logger = Logger.new(log_output)

    # Configure a callback that raises an exception
    Sidekiq::MemoryLogger.configure do |config|
      config.logger = test_logger
      config.callback = ->(job_class, queue, memory_diff) do
        raise StandardError, "callback error"
      end
    end

    # Create new middleware after configuration change
    middleware = Sidekiq::MemoryLogger::Middleware.new

    # Middleware should not raise, but should log the error
    middleware.call(nil, @job, @queue) { sleep 0.01 }

    log_content = log_output.string
    assert_includes log_content, "Sidekiq memory logger callback failed: callback error"
  end
end
