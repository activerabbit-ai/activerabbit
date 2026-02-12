web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -e production -c 25 -q ingest,3 -q alerts,2 -q default -q analysis -q mailers
