lock '3.8.0'

require 'capistrano/console'
require 'json'

# show: http://capistranorb.com/documentation/advanced-features/properties/
## sshでログインするユーザ
# set :user, "XXXXX"
## ssh 設定
# set :ssh_options, :port=>22, :forward_agent=>false, :keys=>"秘密鍵の場所", :passphrase => ""

# chef-repoルートディレクトリ
CHEF_REPO = File.expand_path('..', File.dirname(__FILE__))
# 環境情報
STAGE = env.fetch(:stage)
# Chef-Client Package Url
CHEF_CLIENT_URL = 'https://packages.chef.io/stable/el/6/chef-12.10.24-1.el6.x86_64.rpm'
CHEF_CLIENT_VERSION = CHEF_CLIENT_URL.match(/chef-(?<version>\d+\.\d+).*$/)['version']

# 既存のchef-repoを一旦削除してから展開
FORCE = true

SSH_USER = ENV['USER']

# ログレベル
set :log_level, :debug
# アプリケーション名(任意)
set :application, 'chef'
#set :use_sudo, false
# sudo 時必須
set :pty, true

on roles(:all) do |host|
#  host.user = SSH_USER
end

# server情報の生成
Dir.glob("#{CHEF_REPO}/nodes/#{STAGE}/*.json").each do |_node_file|
  _json = JSON.parse(File.read _node_file)
  if _json["server"].nil?
    server _json["name"], name: _json["name"], user: SSH_USER
  else
    server _json["server"], name: _json["name"], user: SSH_USER
  end
end

########################################################################################
#  TASK
########################################################################################

########################################
# ruby の書式チェック
task :ruby_c do
  run_locally do
    Dir.glob("#{CHEF_REPO}/**/**/*.rb").each do |_f|
      system("sudo chef exec ruby -c #{_f} 1>/dev/null")
    end
  end
end

########################################
# 環境別ノード情報の表示
# chef exec cap development list_server
########################################
task :list_server do
  on roles(:all), in: :parallel do |server|
    puts "STAGE: #{STAGE} SSH_USER: #{server.user}"
    printf(" server: %s node_name: %s\n",server.hostname, server.fetch(:name))
  end
end

########################################
#  uptime
# chef exec cap deveopment uptime
########################################
task :uptime do
  on roles(:all), in: :parallel do |server|
    uptime = capture(:uptime)
    printf("%s(%s) %s\n", server.hostname, server.fetch(:name), uptime)
  end
end

########################################
# MemFree/MemTotal
# chef exec cap development mem
########################################
task :mem do
  on roles(:all) , in: :parallel do |server|
    total = capture("cat  /proc/meminfo | awk '/MemTotal/{print $2}'") 
    free  = capture("cat  /proc/meminfo | awk '/MemFree/{print $2}'")
    printf("%s(%s) %s kb / %s kb \n",server.hostname, server.fetch(:name) , total, free)

  end
end

########################################
# chef
# chef exec cap development chef:all
########################################
namespace :chef do
  task :all  => %w(install archive sync_archive run)
 
  ########################################
  # git pull
  ########################################
  task :git_pull do
    run_locally do
      system("git pull origin master")
    end
  end 
  ########################################
  # chef-clientのインストール
  ########################################
  task :install do
    on roles(:all), in: :parallel do |server|
      chef_v = capture("rpm -qa chef")
      m = chef_v.match(/chef-(?<version>\d+\.\d+).*$/)
      if m.nil?
        printf("%s(%s)  install chef-client\n", server.hostname, server.fetch(:name))
        execute("sudo yum -y install #{CHEF_CLIENT_URL}")
      elsif m["version"].to_f < CHEF_CLIENT_VERSION.to_f
        printf("%s(%s)  update chef-client %s to %s \n", server.hostname, server.fetch(:name), m["version"] , CHEF_CLIENT_VERSION)
        execute("sudo yum -y update #{CHEF_CLIENT_URL}")
      end
    end
  end
  ########################################
  # chef-repoのアーカイブ
  ########################################
  task :archive do
    run_locally do
      execute("sudo touch #{CHEF_REPO}/client.rb && sudo chown #{SSH_USER}:#{SSH_USER} #{CHEF_REPO}/client.rb")
      execute("sudo tar -czf /tmp/chef-repo.tar.gz -C #{File.dirname(CHEF_REPO)} #{File.basename(CHEF_REPO)} --exclude log")
    end
  end
  ########################################
  # アーカイブファイルの転送
  ########################################
  task :sync_archive do
    on roles(:all), in: :parallel do |server|
      system("rsync -v  /tmp/chef-repo.tar.gz #{server.hostname}:/tmp/")
      execute("sudo rm -rf /tmp/#{File.basename(CHEF_REPO)}") if FORCE
      execute("tar -zxf /tmp/chef-repo.tar.gz -C /tmp")
    end
  end
  ########################################
  # 実行
  ########################################
  task :run do
    on roles(:all), in: :parallel do |server|
p File.basename(CHEF_REPO)
     execute("cd /tmp/#{File.basename(CHEF_REPO)} && sudo chef-client -z -j nodes/#{STAGE}/#{server.fetch(:name)}.json --config client.rb")
    end
  end

end


