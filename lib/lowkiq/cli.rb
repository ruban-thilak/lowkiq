module Lowkiq
  class CLI
    def self.instance
      @instance ||= new
    end

    def parse(args = ARGV.dup)
      @options = Lowkiq::OptionParser.call(args)
      set_environment(@options[:environment])
    end

    def run
      if @environment == "development"
        print_banner
        puts "Running in #{RUBY_DESCRIPTION}"
      end

      launch
    end

    def launch
      self_read, self_write = IO.pipe

      puts "Booting Lowkiq Server..."
      @server = Lowkiq::Server.build(@options)

      begin
        puts "Starting processing, hit Ctrl-C to stop"

        @server.start
        @server.join

        while self_read.wait_readable
          signal = self_read.gets.strip
          handle_signal(signal)
        end
      rescue Interrupt
        puts "Shutting down"
        @server.stop
        puts "Bye!"

        # Explicitly exit so busy Processor threads won't block process shutdown.
        exit(0)
      end
    end

    def print_banner
      puts "\e[31m"
      puts lowkiq_banner
      puts "\e[0m"
    end

    def lowkiq_banner
      %{
      #{w}██╗      ██████╗ ██╗    ██╗██╗  ██╗██╗ ██████╗
      #{w}██║     ██╔═══██╗██║    ██║██║ ██╔╝██║██╔═══██╗
      #{w}██║     ██║   ██║██║ █╗ ██║█████╔╝ ██║██║   ██║
      #{w}██║     ██║   ██║██║███╗██║██╔═██╗ ██║██║▄▄ ██║
      #{w}███████╗╚██████╔╝╚███╔███╔╝██║  ██╗██║╚██████╔╝
      #{w}╚══════╝ ╚═════╝  ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝ ╚══▀▀═╝
      #{reset}}
    end

    def w
      "\e[1;31m"
    end

    def reset
      "\e[0m"
    end

    private

    def set_environment(cli_env)
      # APP_ENV is now the preferred ENV term since it is not tech-specific.
      # RAILS_ENV and RACK_ENV are there for legacy support.
      @environment = cli_env || ENV["APP_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
      @options[:environment] = @environment
    end

    SIGNAL_HANDLERS = {
      # Ctrl-C in terminal
      "INT" => ->(cli) { raise Interrupt },
      # TERM is the signal that Lowkiq must exit.
      "TERM" => ->(cli) { raise Interrupt },
      # TTIN is the signal that Lowkiq must dump threads.
      "TTIN" => ->(cli) {
        file = "/tmp/lowkiq_ttin.txt"

        File.delete file if File.exists? file

        File.open(file, 'w') do |file|
          Thread.list.each_with_index do |thread, idx|
            file.write "== thread #{idx} == \n"
            if thread.backtrace.nil?
              file.write "<no backtrace available> \n"
            else
              thread.backtrace.each do |line|
                file.write "#{line} \n"
              end
            end
          end
        end
      }
    }

    def handle_signal(sig)
      puts "Got #{sig} signal"
      SIGNAL_HANDLERS[sig].call(self)
    end
  end
end
