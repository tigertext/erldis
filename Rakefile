task :default => :build

if File.file?('erlang_config.rb') 
  require 'erlang_config'  
else
  puts "erlang_config.rb file is missing."
  puts "You need to fill it with your local configuration."
  puts "An sample has been generated for you."
  File.open("erlang_config.rb",'w') do |file|
    file.write("ERL_TOP=\"<path to your erlang installation>\"\n")
    file.write("EMAKE_COMPILE_OPTIONS = []\n")
  end
  exit(-1)
end

task :build do
  sh "#{ERL_TOP}/bin/erl -make"
end

desc "installs in $ERL_TOP/lib/"
task :install =>  [:build] do |t|
   FileList.new('ebin/*.app').each do |dir|
     #vsn = extract_version_information("vsn.config","vsn").gsub("\"","")
     name = dir.gsub("ebin/","").gsub(".app","")
     destination =  "#{erlang_home}/lib/#{name}"
     puts "#{name} will be installed in #{destination}"
     sh "mkdir -p #{destination}"
     %w{ebin doc include }.each do |d|
       sh "cp -R #{d} #{destination}"
     end
   end
end

def erlang_home
    @erlang_home||=IO.popen("#{ERL_TOP}/bin/erl -noinput -noshell -eval 'io:format(code:root_dir()).' -s init stop").readlines[0] 
end
def extract_version_information(file, type)
  informations = []
  IO.foreach(file) { |line|
    informations << $1 if line =~ /\{#{type},(.*)\}/
  }
  informations[0]
end

task :xref do
  sh "rebar xref"
end

task :build_plt do
  sh 'dialyzer ebin --build_plt --apps erts kernel stdlib inets crypto eunit'
  sh 'mv ~/.dialyzer_plt ~/.erldis_dialyzer_plt'
end

task :analyze do
  sh 'dialyzer --plt ~/.erldis_dialyzer_plt -Wunmatched_returns -Werror_handling -Wrace_conditions -Wbehaviours ebin | grep --color -e "^[^:]*:\|^[^:]*$"'
end

task :updatedeps do
  print "Updating Erlang dependencies..."
  sh "rebar delete-deps && rebar get-deps"
  print " done\n"
end

task :doc do
  sh "mkdir -p doc/html"
  sh "cp src/overview.edoc doc/html"
  sh 'erl -noshell -eval "edoc:files(filelib:wildcard(\"src/*.erl\"), [{dir, \"doc/html\"}, {includes, [\"include\"]}, {source_path, [\"include\", \"src\"]}])" -s init stop'
  sh "cd doc/html && git add . && git commit -m 'New doc version' && git push"
end