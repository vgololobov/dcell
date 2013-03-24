require 'celluloid'
require 'celluloid/zmq'

Celluloid::ZMQ.init

require 'dcell/version'
require 'dcell/actor_proxy'
require 'dcell/directory'
require 'dcell/mailbox_proxy'
require 'dcell/messages'
require 'dcell/node'
require 'dcell/node_manager'
require 'dcell/global'
require 'dcell/responses'
require 'dcell/router'
require 'dcell/rpc'
require 'dcell/future_proxy'
require 'dcell/server'
require 'dcell/info_service'

require 'dcell/registries/redis_adapter'
#require 'dcell/registries/moneta_adapter'

require 'dcell/celluloid_ext'

# Distributed Celluloid
module DCell
  class NotConfiguredError < RuntimeError; end # Not configured yet

  DEFAULT_PORT  = 7777 # Default DCell port
  @config_lock  = Mutex.new

  class << self
    attr_reader :me, :registry

    # Configure DCell with the following options:
    #
    # * id: to identify the local node, defaults to hostname
    # * addr: 0MQ address of the local node (e.g. tcp://4.3.2.1:7777)
    # *
    def setup(options = {})
      # Stringify keys :/
      options = options.inject({}) { |h,(k,v)| h[k.to_s] = v; h }

      @config_lock.synchronize do
        @configuration = {
          'id'   => generate_node_id,
          'addr' => "tcp://127.0.0.1:#{DEFAULT_PORT}",
          'registry' => {'adapter' => 'redis', 'server' => 'localhost'}
        }.merge(options)

        @me = Node.new @configuration['id'], @configuration['addr']

        registry_adapter = @configuration['registry'][:adapter] || @configuration['registry']['adapter']
        raise ArgumentError, "no registry adapter given in config" unless registry_adapter

        registry_class_name = registry_adapter.split("_").map(&:capitalize).join << "Adapter"

        begin
          registry_class = DCell::Registry.const_get registry_class_name
        rescue NameError
          raise ArgumentError, "invalid registry adapter: #{@configuration['registry']['adapter']}"
        end

        @registry = registry_class.new(@configuration['registry'])

        addr = @configuration['public'] || @configuration['addr']
        DCell::Directory.set @configuration['id'], addr
      end

      me
    end

    # Obtain the local node ID
    def id
      raise NotConfiguredError, "please configure DCell with DCell.setup" unless @configuration
      @configuration['id']
    end

    # Obtain the 0MQ address to the local mailbox
    def addr; @configuration['addr']; end
    alias_method :address, :addr

    # Attempt to generate a unique node ID for this machine
    def generate_node_id
      `hostname`.strip # Super creative I know
    end

    # Run the DCell application
    def run
      DCell::SupervisionGroup.run
    end

    # Run the DCell application in the background
    def run!
      DCell::SupervisionGroup.run!
    end

    # Start combines setup and run! into a single step
    def start(options = {})
      setup options
      run!
    end
  end

  # DCell's actor dependencies
  class SupervisionGroup < Celluloid::SupervisionGroup
    supervise NodeManager, :as => :node_manager
    supervise Server,      :as => :dcell_server
    supervise InfoService, :as => :info
  end

  Logger = Celluloid::Logger
end
