#!/usr/bin/ruby

require "optparse"
require "net/http"
require "uri"
require "json"
require "yaml"
require "base64"
require "io/console"
require "curses"

# Flags and options
VERSION = "0.9"

$options = {
  url: "http://task-track.herokuapp.com/api",
  status: "finished",
  date: Time.now.strftime("%Y-%m-%d")
}

$config = File.join(Dir.home, ".timetrack.yml")
$editor = "vim"

$tasks = ARGV

def getopts!
  OptionParser.new do |opts|
    opts.on("-e", "--email email", "Email") do |v|
      $options[:email] = v
    end
    opts.on("-p", "--password password", "Password") do |v|
      $options[:password] = v
    end
    opts.on("-u", "--url url", "Connection url") do |v|
      $options[:url] = v
    end
    opts.on("-h", "--help", "Help page") do |v|
      print_help
    end
    opts.on("-v", "--version", "Version") do |v|
      puts VERSION
    end
    opts.on("-n", "--name name", "Time entry name") do |v|
      $options[:name] = v
    end
    opts.on("-t", "--real-time time", "Real time") do |v|
      $options[:real_time] = v
    end
    opts.on("-r", "--project name", "Project name") do |v|
      $options[:project] = v
    end
    opts.on("-d", "--date date", "Date") do |v|
      $options[:date] = v
    end
    opts.on("-s", "--status status", "Status") do |v|
      $options[:status] = v
    end
    opts.on("", "--description", "Description") do |v|
      $options[:description] = v
    end
  end.parse!
end


# Print help
def print_help
  puts %Q{\
Usage: timetrack.rb [subject action] [options]

subjects:
  te              - Time entries

actions:
  get             - Get subject (index action)
  create          - Create subject (create action)

options:
  -e, --email         Email
  -p, --password      Password
  -u, --url           Url to TimeTrack api
  -n, --name          Subject name
  -t, --real-time     Real time for time entries
  -r, --project       Project name for time entries
  -d, --date          Date for time entries (default: today)
  -s, --status        Status for time entries (default: finished)

  -h, --help          Print this page
  -v, --version       Print version

TimeTrack console client.

Authors:
  Pbs:          pitabrus@gmail.com
...

Bugs: planned :3

Version: #{VERSION} }
end


# Require option anyway
def required_option(name, option)
  unless option
    # BUG: `print` raise error. Why?
    printf "Type #{name}: "
    option = STDIN.gets.chomp
  end
  option
end


def required_password(password)
  unless password
    printf "Type password: "
    password = IO::console.noecho { STDIN.gets.chomp }
    puts ""
  end
  password
end


def encode_logpass
  #TODO: digest authentication
  email = required_option("email", $options[:email])
  pass = required_password($options[:password])
  Base64.strict_encode64("#{email};#{pass}")
end


def load_config!
  if File.exists?($config)
    conf = YAML.load_file($config)
    $editor = conf["editor"]
    conf["defaults"].each do |k, v|
      $options[k.to_sym] = v
    end
  end
end


def window_print(text)
  # if(READER == R_KIRILL) return;

  # Pretty print with scroll
  Curses.init_screen()
  win = Curses::Window.new(0, 0, 0, 0)
  win.keypad(true)

  screen_width = win.maxx
  screen_height = win.maxy

  height = screen_height - 3
  position = 0

  max_position = text.split("\n").count - height

  loop do
    win.clear
    output = text.split("\n")[position...(position+height)].join("\n")
    output << "\n\nUp and down to scroll, q to quit: "
    win.addstr(output)
    win.refresh

    c = win.getch
    case c
    when Curses::Key::DOWN
      position = position < max_position ? position+1 : max_position
    when Curses::Key::UP
      position = position > 0 ? position-1 : 0
    when ?q
      break
    end
  end
end


# Request class
class Request
  def initialize(name)
    @name = name
  end


  def get
    url = File.join($options[:url], @name)
    uri = URI.parse(url)
    uri.query = "digest=#{encode_logpass}"
    JSON.parse(Net::HTTP.get_response(uri).body)
  end


  def create
    url = File.join($options[:url], @name)
    uri = URI.parse(url)
    uri.query = "digest=#{encode_logpass}"
    response = Net::HTTP.post_form(uri, {
      name:      required_option("time entry name", $options[:name]),
      project:   required_option("project name", $options[:project]),
      real_time: required_option("real time", $options[:real_time]),
      date:      $options[:date],
      status:    $options[:status],
    })
    JSON.parse(response.body)
  end


  def print(*response_fields)
    response = self.get
    buffer = ""
    if r = response["response"]
      r[@name].each do |u|
        buffer << self.perform_row(response_fields, u)
      end

      window_print(buffer)

    elsif response["error"]
      # TODO: colored print
      response["error"]["messages"].each do |e|
        abort e
      end
    else
      abort "Bad response, please report me about this!"
    end
  end
  #TODO: Articles, Statistics


  protected

  def perform_row(fields, record)
    fields.map { |f| "%-#{f[1]}s" % record[f[0]].to_s[0...f[1]] }.join(" ") + "\n"
  end
end




load_config!
getopts!


case $tasks[0]
when "time-entries", "te"
  time_entries = Request.new("time_entries")
  case $tasks[1]
  when "get"
    time_entries.print(["id", 4], ["project", 10], ["name", 15], ["real_time", 5])
  when "create", "c"
    response = time_entries.create
    if response["response"]
      puts response["response"]["status"]
    elsif response["error"]
      response["error"]["messages"].each do |e|
        abort e
      end
    else
      abort "Bad response, please report me about this!"
    end
  end

when "articles"
  articles = Request.new("articles")
  case $tasks[1]
  when "get"
    puts articles.print(["importance", 1], ["title", 15], ["short_description", 40])
  when "create", "c"
    abort "Not supported yet"
  end
end
