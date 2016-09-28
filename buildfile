##########################GO-LICENSE-START################################
# Copyright 2014 ThoughtWorks, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################GO-LICENSE-END##################################

require 'fileutils'

include FileUtils

# Generated by Buildr 1.3.4, change to your liking
# Version number for this release
VERSION_NUMBER = ENV['GO_VERSION'] || '16.2.0'

# Group identifier for your projects
GROUP = "cruise"

GO_TRUNK_DIRNAME = ENV['GO_TRUNK_DIR'] || 'gocd'
GO_PLUGINS_DIRNAME = ENV['GO_PLUGINS_DIR'] || 'go-plugins'
GO_JOB_RUN_COUNT = ENV['GO_JOB_RUN_COUNT']
GO_JOB_RUN_INDEX = ENV['GO_JOB_RUN_INDEX']

GAUGE_TAGS = ENV["GAUGE_TAGS"]||'smoke,\!manual'
LOAD_BALANCED = GO_JOB_RUN_COUNT && GO_JOB_RUN_INDEX
FIREFOX_BROWSER = ENV['twist_in_firefox'] || 'N'

#discover the revision and commit digest
def stdout_of command
  Util.win_os? && command.gsub!(/'/, '"')
  stdout = `#{command}`
  $?.success? || fail("`#{command}` failed")
  stdout
end

def drop_recreate_pgsql_db
  (puts "Not recreating DB since PostgreSQL is not being used."; return) if ENV['USE_POSTGRESQL'] != 'Y'

  generated_db_name="#{ENV['DB_NAME_PREFIX']}__#{ENV['GO_JOB_NAME']}__#{ENV['GO_STAGE_NAME']}__#{ENV['GO_PIPELINE_NAME']}".gsub(/[^0-9a-zA-Z]/, "_")[0..62]
  ENV['POSTGRES_DB_NAME_TO_USE'] = "#{ENV['DB_NAME_PREFIX'] ? generated_db_name : "cruise"}"
  ENV['POSTGRES_DB_HOST_TO_USE'] = "#{ENV['DB_HOST'] || "localhost"}"


  puts "Using DB: #{ENV['POSTGRES_DB_NAME_TO_USE']} on host: #{ENV['POSTGRES_DB_HOST_TO_USE']}"

  drop_db_command = "java -jar tools/run_with_postgres.jar #{ENV['POSTGRES_DB_HOST_TO_USE']} 5432 '' postgres '' 'DROP DATABASE IF EXISTS #{ENV['POSTGRES_DB_NAME_TO_USE']}'"
  create_db_command = "java -jar tools/run_with_postgres.jar #{ENV['POSTGRES_DB_HOST_TO_USE']} 5432 '' postgres '' 'CREATE DATABASE #{ENV['POSTGRES_DB_NAME_TO_USE']}'"
  system("#{drop_db_command} && #{create_db_command}") || (puts "Failed to drop and recreate DB. Tried running: #{drop_db_command} && #{create_db_command}"; exit 1)

  puts "Recreated DB: #{ENV['POSTGRES_DB_NAME_TO_USE']}"
end

# Specify Maven 2.0 remote repositories here, like this:
repositories.remote << "http://repo1.maven.org/maven2/"

drop_recreate_pgsql_db

desc "The Cruise project"
define "cruise" do |project|
  compile.options[:other] = %w[-encoding UTF-8]
  compile.with ['jdom:jdom:jar:1.0']

  TMP_DIR = test.options[:properties]['java.io.tmpdir'] = _('target/temp')
  mkpath TMP_DIR

  manifest['Cruise-Version'] = VERSION_NUMBER

  project.version = VERSION_NUMBER
  project.group = GROUP



# if (Util.win_os?)
#		if (FIREFOX_BROWSER == 'N')
#			cp(_('src','test','java', 'twist.win.properties'), _('target', 'twist.properties'))
#		end
#		if (FIREFOX_BROWSER == 'Y')
#			cp(_('src','test','java', 'twist.firefox.win.properties'), _('target', 'twist.properties'))
#		end
 #end

  clean do
    mkpath TMP_DIR
  end

end

task :resolve_dependencies do
  _cruise = project('cruise')
  artifacts(_cruise.compile.dependencies).each(&:invoke)
  cp _cruise.compile.dependencies.collect { |t| t.to_s }, _cruise.path_to('tempo')
end

task :copy_plugins do
  mkdir_p "target/go-server-#{VERSION_NUMBER}/plugins/external"
  cp_r "../#{GO_PLUGINS_DIRNAME}/target/go-plugins-dist/.", "target/go-server-#{VERSION_NUMBER}/plugins/external"
  rm "target/go-server-#{VERSION_NUMBER}/plugins/external/yum-repo-exec-poller.jar"
end

task :copy_server do
  mkdir_p "target"
  cp_r "../#{GO_TRUNK_DIRNAME}/target/go-server-#{VERSION_NUMBER}", "target"
end

task :copy_agent do
  mkdir_p "target"
  cp_r "../#{GO_TRUNK_DIRNAME}/target/go-agent-#{VERSION_NUMBER}", "target"
  cp "target/go-agent-#{VERSION_NUMBER}/agent.sh", "src/test/java/com/thoughtworks/cruise/preconditions/start-twist-agent.sh"
end

task :setup => [:copy_agent, :copy_server, :copy_plugins] do
end


task :kill_server do
  if Util.win_os?
    system("target\go-server-#{VERSION_NUMBER}\stop-server.bat")
  else
    system("pkill -f cruise.jar")
  end
end

def kill_gauge
  system("cmd /c scripts\\kill_gauge.bat")
end

task :killgauge do
  if Util.win_os?
    kill_gauge
  end
end

task :agent_cleanup do
  if Util.win_os?
    system("cmd /c target\\go-server-#{VERSION_NUMBER}\\stop-server.bat")
    system("cmd /c scripts\\kill_all_go_instances.bat")
    kill_gauge
 else
    sh "scripts/kill_all_go_instances.sh"
    sh "scripts/cleanup-agents.sh"
    rm_rf "target"
    mkdir_p "target"
  end
end

task :cleanup_test_agents do
   if !Util.win_os?
     sh "scripts/cleanup-agents.sh"
   end
end

task :setup_go do
  if Util.win_os?
    system("cmd /c scripts\\setup-go.bat")
    system("mvn -B -V dependency:resolve dependency:copy-dependencies -DoutputDirectory=libs/")
  else
    sh "scripts/setup-go.sh"
    sh "mvn -B -V dependency:resolve dependency:copy-dependencies -DoutputDirectory=libs/"
  end
end

task :gauge_specs do

 if Util.win_os?
    system("cmd /c scripts\\enable_ie_proxy.bat enable ")
 end

 if LOAD_BALANCED
  sh "gauge --tags=#{GAUGE_TAGS} -n=#{GO_JOB_RUN_COUNT} -g=#{GO_JOB_RUN_INDEX} specs"
 else
  sh "gauge --tags=#{GAUGE_TAGS} specs"
 end

 if Util.win_os?
    system("cmd /c scripts\\enable_ie_proxy.bat disable ")
 end
end

task "no-test" do
  ENV["test"]="no"
end

task "start_server" do
  sh "cd scripts; ./start-server.sh"
end

task 'bump-schema' do
  version = ENV['VERSION'].to_s

  raise "Please provide VERSION" if version.empty?
  sh("curl --fail --location --silent https://raw.githubusercontent.com/gocd/gocd/master/config/config-server/resources/cruise-config.xsd > src/test/java/cruise-config.xsd")

  Dir["./src/test/java/config/*.xml"].each do |path|
    content = File.read(path)
    if content =~ /xsi:noNamespaceSchemaLocation="cruise-config.xsd"/
      puts "Replacing content in #{path}"
      content = content.gsub(/schemaVersion="\d+"/, %Q{schemaVersion="#{version}"})
      open(path, 'w') {|f| f.write(content)}
    end
  end

  java_file = 'src/test/java/com/thoughtworks/cruise/util/CruiseConstants.java'
  cruiseconstants_contents = File.read(java_file)

  new_contents = []
  cruiseconstants_contents.each_line do |line|
    if line =~ /CONFIG_SCHEMA_VERSION/
      line = "    public static final int CONFIG_SCHEMA_VERSION = #{version};\n"
    else
      line
    end
    new_contents << line
  end

  open(java_file, 'w') do |f|
     f.write(new_contents.join)
   end
end
