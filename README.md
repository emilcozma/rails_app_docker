# Dockerize a Ruby on rails app with redis and sidekiq

## Prerequisites
- docker
- docker compose

## To build the image:
```bash
docker build -t rails-toolbox -f Dockerfile.rails .
```

### Create the project
```bash
docker run -it -v $PWD:/opt/app rails-toolbox rails new --skip-bundle app
```

### Existing project
Copy existing app to src folder

## Modifying the Gemfile
Add the following lines to the bottom of your Gemfile: 
```json
gem 'unicorn', '~> 6.1.0'
gem 'pg', '~> 1.3.5'
gem 'sidekiq', '~> 6.4.2'
gem 'redis-rails', '~> 5.0.2'
```

## DRYing Out the Database Configuration
Change your config/database.yml to look like this: 
```json
---

development:
  url: <%= ENV['DATABASE_URL'].gsub('?', '_development?') %>

test:
  url: <%= ENV['DATABASE_URL'].gsub('?', '_test?') %>

staging:
  url: <%= ENV['DATABASE_URL'].gsub('?', '_staging?') %>

production:
  url: <%= ENV['DATABASE_URL'].gsub('?', '_production?') %>
```

## DRYing Out the Secrets File
Create a config/secrets.yml file, it should look like this: 
```json
development: &default
  secret_key_base: <%= ENV['SECRET_TOKEN'] %>

test:
  <<: *default

staging:
  <<: *default

production:
  <<: *default
```

## Editing the Application Configuration
Add the following lines to your config/application.rb: 
```json
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
```

## Creating the Unicorn Config
Next, create the config/unicorn.rb file and add the following content to it: 
```json
# Heavily inspired by GitLab:
# https://github.com/gitlabhq/gitlabhq/blob/master/config/unicorn.rb.example

worker_processes ENV['WORKER_PROCESSES'].to_i
listen ENV['LISTEN_ON']
timeout 30
preload_app true
GC.respond_to?(:copy_on_write_friendly=) && GC.copy_on_write_friendly = true

check_client_connection false

before_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.disconnect!

  old_pid = "#{server.config[:pid]}.oldbin"
  if old_pid != server.pid
    begin
      sig = (worker.nr + 1) >= server.worker_processes ? :QUIT : :TTOU
      Process.kill(sig, File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
    end
  end
end

after_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.establish_connection
end
```

## Creating the Sidekiq Initialize Config
Now you can also create the config/initializers/sidekiq.rb file and add the following code to it:
```json
sidekiq_config = { url: ENV['JOB_WORKER_URL'] }

Sidekiq.configure_server do |config|
  config.redis = sidekiq_config
end

Sidekiq.configure_client do |config|
  config.redis = sidekiq_config
end
```

## Whitelist Docker Host
Edit the config/environment/development.rb file and add the following line:
```json
config.hosts << "app"
```

## Create the Environment Variable File
```bash
cp .dist/.env .env
```

Generate new secret token and update the .env file
```bash
openssl rand -base64 64
```

## Configuring Ngnix
```json
# reverse-proxy.conf

server {
    listen 8020;
    server_name example.org;

    location / {
        proxy_pass http://app:8010;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

## Running Everything
```bash
docker compose up --build
```

## Initialize the Database
```bash
docker compose run --rm app rake db:reset
docker compose run --rm app rake db:migrate
```

## Testing It Out
Head over to http://localhost:8020