require "eventmachine"

require "thin/system"
require "thin/listener"
require "thin/backends/prefork"
require "thin/backends/single_process"

module Thin
  # The uterly famous Thin server.
  #
  # == Listening
  # Create and start a new server listenting on port 3000 and forwarding all requests to +app+.
  #
  #   server = Thin::Server.new(app)
  #   server.listen 3000
  #   server.start
  #
  # == Using a custom protocol
  # You can implement your own protocol handler that will parse and process requests. This is simply done by
  # implementing a typical EventMachine +Connection+ class or module.
  #
  #   class Echo < EventMachine::Connection
  #     attr_accessor :server
  #
  #     def receive_data(data)
  #       send_data data
  #       close_connection_after_writing
  #     end
  #   end
  #
  #   server = Thin::Server.new
  #   server.listen 3000, :protocol => Echo
  #   server.start
  #
  # == Preforking and workers
  # If fork(2) is available on your system, Thin will try to start workers to process requests.
  # By default the number of workers will be based on the number of processors on your system.
  # Configure this using the +worker_processes+ attribute.
  # However, if fork(2) or if +worker_processes+ if equal to +0+, Thin will run in a single process
  # with limited features.
  #
  # == Single process mode
  # In this mode, Thin features will be limited:
  # - no log files
  # - no signal handling (only exits on INT).
  #
  # This mode is only intended as a fallback for systems with no fork(2) system call.
  #
  # You can force this mode by setting +worker_processes+ to +0+.
  #
  # == Controlling with signals
  # - *WINCH*: Gracefully kill all workers but keep master alive
  # - *TTIN*: Increase number of workers
  # - *TTOU*: Decrease number of workers
  # - *QUIT*: Kill workers and master in a graceful way
  # - *TERM*, *INT*: Kill workers and master immediately
  class Server
    # Application called with the request that produces the response.
    attr_accessor :app

    # A tag that will show in the process listing
    attr_accessor :tag

    # Number of child worker processes.
    # Setting this to 0 will result in running in a single process with limited features.
    # Default: number of processors available or 0 if +fork+ is not available.
    attr_accessor :worker_processes

    # Maximum number of file descriptors that the worker may open.
    # Default: 1024
    attr_accessor :worker_connections

    # Workers are killed if they don't check-in under +timeout+ seconds.
    # Default: 30
    attr_accessor :timeout

    # Path to the file in which the PID is saved.
    # Default: ./thin.pid
    attr_accessor :pid_path

    # Path to the file in which standard output streams are redirected.
    # Default: none, outputs to stdout
    attr_accessor :log_path

    # Set to +true+ to use epoll event model.
    attr_accessor :use_epoll

    # Set to +true+ to use kqueue event model.
    attr_accessor :use_kqueue

    # Set the backend handling the connections to the clients.
    attr_writer :backend

    # Listeners currently registered on this server.
    # @see Thin::Listener
    attr_accessor :listeners

    # Object that is +call+ed before forking a worker process inside the master process.
    attr_accessor :before_fork

    # Object that is +call+ed after forking a worker process inside the worker process.
    attr_accessor :after_fork

    def initialize(app=nil)
      @app = app
      @timeout = 30
      @pid_path = "./thin.pid"
      @log_path = nil
      @worker_connections = 1024

      if System.supports_fork?
        # One worker per processor
        @worker_processes = System.processor_count
      else
        # No workers, runs in a single process.
        @worker_processes = 0
      end

      @listeners = []
    end

    # Backend handling connections to the clients.
    def backend
      @backend ||= begin
        if prefork?
          Backends::Prefork.new(self)
        else
          Backends::SingleProcess.new(self)
        end
      end
    end

    # Listen for incoming connections on +address+.
    # @example
    #   listen 3000 # port number
    #   listen "0.0.0.0:8008", :backlog => 80
    #   listen "[::]:8008", :ipv6_only => true
    #   listen "/tmp/thin.sock"
    # @param address [String, Integer] address to listen on. Can be a port number of host:port.
    # @option options [Boolean] :tcp_no_delay (true) Disables the Nagle algorithm for send coalescing.
    # @option options [Boolean] :ipv6_only (false) do not listen on IPv4 interface.
    # @option options [Integer] :backlog (1024) Maximum number of clients in the listening backlog.
    # @option options [Symbol, String, Class] :protocol (:http) Protocol name or class to use to process connections.
    def listen(address, options={})
      listener = Listener.parse(address)
      options = {
        # Default values
        :protocol => :http,
        :tcp_no_delay => true,
        :ipv6_only => false,
        :backlog => 1024,
      }.merge(options)
      listener.protocol = options[:protocol]
      listener.tcp_no_delay = options[:tcp_no_delay]
      listener.ipv6_only = options[:ipv6_only]
      listener.listen(options[:backlog])
      @listeners << listener
    end

    # Starts the server and open a listening socket for each +listeners+.
    # @param daemonize Daemonize the process after starting.
    def start(daemonize=false)
      puts "Starting #{to_s} ..."

      # Configure EventMachine
      EM.epoll = @use_epoll unless @use_epoll.nil?
      EM.kqueue = @use_kqueue unless @use_kqueue.nil?
      @worker_connections = EM.set_descriptor_table_size(@worker_connections)

      @listeners.each do |listener|
        puts "Listening with #{listener}"
      end
      puts "CTRL+C to stop"

      backend.start(daemonize) do
        @listeners.each do |listener|
          EM.attach_server(listener.socket, listener.protocol_class) do |c|
            c.server = self if c.respond_to?(:server=)
            c.listener = listener if c.respond_to?(:listener=)
          end
        end
      end
    rescue
      stop
      raise
    end

    # Stops the server and close all listeners.
    def stop
      puts "Stopping ..."
      @listeners.each { |listener| listener.close }
    end
    alias :shutdown :stop

    # Returns +true+ if the server will fork workers or +false+ if it will run in a single process.
    def prefork?
      @worker_processes > 0
    end

    # Procline of the process when the server is running.
    def to_s
      "Thin" + (@tag ? " [#{@tag}]" : "")
    end
  end
end
