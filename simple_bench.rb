#!/usr/bin/env ruby

# TODO: script mode that installs Rubies
# TODO: jruby

Dir.chdir(File.expand_path __dir__)

require "tempfile"

RUBIES = [
    #{
    #    name: "2.0.0-p0",
    #    prefix: "2.0.0",
    #    rvm: "ruby-2.0.0-p0",
    #},
    {
        name: "2.0.0-p648",
        prefix: "2.0.0p648",
        rvm: "ruby-2.0.0-p648",
    },
    #{
    #    name: "2.1.10",
    #},
    #{
    #    name: "2.2.10",
    #},
    #{
    #    name: "2.3.8",
    #},
    #{
    #    name: "2.4.5",
    #},
    {
        name: "2.5.3",
    }
]

# ab -c $CONCURRENCY -n $WARMUP_ITERS -l $URL
# ab -c $CONCURRENCY -n $BENCHMARK_ITERS -l -e rsb.csv $URL

available = `rvm list strings`
if available.strip == ""
    raise "Can't get list of available rubies!"
end
available_rubies = available.strip.split("\n")

RUBIES.each do |ruby_info|
    raise "Ruby has no name! #{ruby_info.inspect}" unless ruby_info[:name]
    unless ruby_info[:prefix]
        ruby_info[:prefix] = ruby_info[:name].gsub("-", "").sub("ruby", "")
    end
    unless ruby_info[:rvm]
        unless ruby_info[:name]["ruby-"]
            ruby_info[:rvm] = "ruby-" + ruby_info[:name]
        end
    end
end

warmup_iters = 100
benchmark_iters = 10_000
port = 4323
extra_args = "" # "-c #{concurrency}"
url = "http://127.0.0.1:#{port}/simple_bench/static"

VERBOSE = true

# Checked system - error if the command fails
def csystem(cmd, err, opts = {})
  print "Running command: #{cmd.inspect}\n" if opts[:debug] || opts["debug"]
  if VERBOSE
    system(cmd, out: $stdout, err: $stderr)
  else
    out = `#{cmd}`
  end
  unless $?.success? || opts[:fail_ok] || opts["fail_ok"]
    puts "Error running command:\n#{cmd.inspect}"
    puts "Output:\n#{out}\n=====" #if out
    raise err
  end
end

RUBIES.each do |ruby_info|
    if available_rubies.include?(ruby_info[:rvm])
        puts "RVM list includes #{ruby_info[:rvm].inspect} - running script..."
    else
        puts "RVM list does not include #{ruby_info[:rvm].inspect} - skipping!"
        next
    end
    script = <<SCRIPT
#!/bin/bash -l

function rails_cleanup {
  kill -s hup `ps x | grep "rails server -p #{port}" | grep -v grep | cut -f1 -d" "`
  sleep 1
  kill -s term `ps x | grep "rails server -p #{port}" | grep -v grep | cut -f1 -d" "`
}
echo Check whether Rails server is already incorrectly running
rails_cleanup

#set -x

rvm use #{ruby_info[:name]}

# We get an error here - why?
pushd widget_tracker

set -e

BUNDLE_GEMFILE="Gemfile.#{ruby_info[:name]}" bundle         # Make sure gems are installed
BUNDLE_GEMFILE="Gemfile.#{ruby_info[:name]}" bundle exec rake db:migrate  # Make sure DB is up to date

# This won't notice if Rails fails horribly, which can happen if the old process wasn't cleaned correctly.
BUNDLE_GEMFILE="Gemfile.#{ruby_info[:name]}" RAILS_ENV=production rails server -p #{port} &
trap rails_cleanup EXIT

echo Waiting for successful request
while ! curl #{url}; do
    echo Waiting for Rails server to be available
    sleep 0.5
done
echo Completed successful request

set +e # pushd and popd seem to fail weirdly here... Maybe it's RVM?

popd

BUNDLE_GEMFILE="Gemfile.#{ruby_info[:name]}" ab #{extra_args} -n #{warmup_iters} -l #{url}
BUNDLE_GEMFILE="Gemfile.#{ruby_info[:name]}" ab #{extra_args} -n #{benchmark_iters} -g #{ruby_info[:prefix]}_bench_rsb.gnuplot #{url}
kill %1
SCRIPT

    Tempfile.open('rsb', '/tmp') do |file|
        file.write(script)
        file.close

        cmd = "/bin/bash -l #{file.path}"
        csystem cmd, "Can't run benchmark script for #{ruby_info[:name].inspect}!"
    end
end