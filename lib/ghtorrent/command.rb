require 'rubygems'
require 'trollop'
require 'daemons'
require 'etc'

require 'ghtorrent/settings'
require 'version'

module GHTorrent

  # Base class for all GHTorrent command line utilities. Provides basic command
  # line argument parsing and command bootstraping support. The order of
  # initialization is the following:
  # prepare_options
  # validate
  # go
  class Command

    include GHTorrent::Settings

    # Specify the run method for subclasses.
    class << self
      def run(args = ARGV)
        attr_accessor :args
        attr_accessor :settings
        attr_accessor :name
        attr_accessor :options

        command = new()

        command.name = self.class.name
        command.args = args

        command.process_options
        command.validate

        command.settings = YAML::load_file command.options[:config]

        unless command.options[:addr].nil?
          command.settings = command.override_config(command.settings,
                                                     :attach_ip,
                                                     command.options[:addr])
        end

        unless command.options[:username].nil?
          command.settings = command.override_config(command.settings,
                                                     :github_username,
                                                     command.options[:username])
        end

        unless command.options[:password].nil?
          command.settings = command.override_config(command.settings,
                                                     :github_passwd,
                                                     command.options[:password])
        end

        begin
          command.go
        rescue => e
          STDERR.puts e.message
          if command.options.verbose
            STDERR.puts e.backtrace.join("\n")
          else
            STDERR.puts e.backtrace[0]
          end
          exit 1
        end
      end
    end

    # Specify and parse top-level command line options.
    def process_options
      command = self
      @options = Trollop::options(command.args) do

        command.prepare_options(self)

        banner <<-END
Standard options:
        END

        opt :config, 'config.yaml file location', :short => 'c',
            :default => 'config.yaml'
        opt :verbose, 'verbose mode', :short => 'v'
        opt :addr, 'ip address to use for performing requests', :short => 'a',
            :type => String
        opt :username, 'Username at Github', :short => 's', :type => String
        opt :password, 'Password at Github', :type => String
      end
    end

    # Get the version of the project
    def version
      IO.read(File.join(File.dirname(__FILE__), '..', '..', 'VERSION'))
    end

    # This method should be overriden by subclasses in order to specify,
    # using trollop, the supported command line options
    def prepare_options(options)
    end

    # Examine the validity of the provided options in the context of the
    # executed command. Subclasses can also call super to also invoke the checks
    # provided by this class.
    def validate
      if options[:config].nil?
        unless (file_exists?("config.yaml"))
          Trollop::die "No config file in default location (#{Dir.pwd}). You
                        need to specify the #{:config} parameter. Read the
                        documentation on how to create a config.yaml file."
        end
      else
        Trollop::die "Cannot find file #{options[:config]}" \
          unless file_exists?(options[:config])
      end

      unless @options[:user].nil?
        if not Process.uid == 0
          Trollop::die "Option --user (-u) can only be specified by root"
        end
          begin
            Etc.getpwnam(@options[:user])
          rescue ArgumentError
            Trollop::die "No such user: #{@options[:user]}"
          end
      end
    end

    # Name of the command that is currently being executed.
    def command_name
      File.basename($0)
    end

    # The actual command code.
    def go
    end

    def override_config(config_file, setting, new_value)
      puts "Overriding configuration #{setting}=#{config(setting)} with cmd line #{new_value}"
      merge_config_values({setting => new_value})
    end

    private

    def file_exists?(file)
      begin
        File::Stat.new(file)
        true
      rescue
        false
      end
    end
  end

end
# vim: set sta sts=2 shiftwidth=2 sw=2 et ai :
