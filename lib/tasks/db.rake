namespace :db do
  desc "Refresh materialized views for dashboards"
  task refresh_materialized_views: :environment do
    RefreshMaterializedViews.call
    puts "Materialized views have been refreshed"
  end

  desc "Generate fake Patient data"
  task seed_patients: :environment do
    abort "Can't run this task in env:#{ENV["SIMPLE_SERVER_ENV"]}!" if ENV["SIMPLE_SERVER_ENV"] == "production"
    Seed::Runner.new.call
  end

  desc "Clear patient data, regenerate patient seed data, and refresh materialized views"
  task purge_and_reseed: [:purge_users_data, :seed_patients, :refresh_materialized_views]

  desc "Purge all Patient data and refresh materialized views"
  task purge_users_data: :environment do
    abort "Can't run this task in #{ENV["SIMPLE_SERVER_ENV"]}!'" if ENV["SIMPLE_SERVER_ENV"] == "production"

    require "tasks/scripts/purge_users_data"
    PurgeUsersData.perform

    RefreshMaterializedViews.call
  end

  desc "Truncate ALL application tables"
  task truncate: :environment do
    abort "Can't run this task in #{SimpleServer.env}!" if SimpleServer.env.production?
    unless ENV.key?("FORCE_TRUNCATE")
      abort "Are you sure you want to truncate ALL TABLES? If so, rerun with FORCE_TRUNCATE set as an env var"
    end
    Seed::ConsoleLogger.announce("hey")
    internal_tables = ["schema_migrations", "ar_internal_metadata"]
    connection = ActiveRecord::Base.connection
    app_tables = connection.tables.reject { |table| table.in?(internal_tables) }.sort
    app_tables.each do |table|
      command = "TRUNCATE #{table} CASCADE"
      puts command
      connection.execute(command)
    end
    puts "Done!"
  end
end

Rake::Task["db:seed"].enhance do
  Rake::Task["db:refresh_materialized_views"].invoke
end
