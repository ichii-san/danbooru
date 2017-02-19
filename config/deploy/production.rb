set :user, "serval"
set :rails_env, "production"
server "friendz.japari.me", :roles => %w(web app db), :primary => true, :user => "serval"
server "friends.japari.me", :roles => %w(web app), :user => "serval"

set :linked_files, fetch(:linked_files, []).push(".env.production")
