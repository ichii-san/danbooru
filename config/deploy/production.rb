set :user, "danbooru"
set :rails_env, "production"
server "friendz.japari.me", :roles => %w(web app db), :primary => true, :user => "danbooru"
server "friends.japari.me", :roles => %w(web app), :user => "danbooru"

set :linked_files, fetch(:linked_files, []).push(".env.production")
