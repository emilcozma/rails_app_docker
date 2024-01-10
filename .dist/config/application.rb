# ...

module App
  class Application < Rails::Application
    config.load_defaults 7.0

    config.log_level = :debug
    config.log_tags  = [:subdomain, :uuid]
    config.logger    = ActiveSupport::TaggedLogging.new(Logger.new(STDOUT))

    config.cache_store = :redis_store, ENV['CACHE_URL'],
                         { namespace: 'app::cache' }

    config.active_job.queue_adapter = :sidekiq
  end
end
