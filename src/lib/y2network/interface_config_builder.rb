# Copyright (c) [2019] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.
require "yast"
require "forwardable"

require "y2network/connection_config"
require "y2network/hwinfo"
require "y2network/startmode"
require "y2network/boot_protocol"
require "y2network/ip_address"
require "y2firewall/firewalld"
require "y2firewall/firewalld/interface"

module Y2Network
  # Collects data from the UI until we have enough of it to create a
  # {Y2Network::ConnectionConfig::Base} object.
  class InterfaceConfigBuilder
    include Yast::Logger
    extend Forwardable

    # Load fresh instance of interface config builder for given type.
    # It can be specialized type or generic, depending if specialized is needed.
    # @param type [Y2Network::InterfaceType,String] type of device or its short name
    # @param config [Y2Network::ConnectionConfig::Base, nil] existing configuration of device or nil
    #   for newly created
    def self.for(type, config: nil)
      if !type.is_a?(InterfaceType)
        type = InterfaceType.from_short_name(type) or raise "Unknown type #{type.inspect}"
      end

      require "y2network/interface_config_builders/#{type.file_name}"
      InterfaceConfigBuilders.const_get(type.class_name).new(config: config)
    rescue LoadError => e
      log.info "Specialized builder for #{type} not found. Falling back to default. #{e.inspect}"
      new(type: type, config: config)
    end

    # @return [String] Device name (eth0, wlan0, etc.)
    attr_reader :name
    # @return [Y2Network::InterfaceType] type of @see Y2Network::Interface which
    #   is intended to be build
    attr_reader :type
    # @return [Y2Network::ConnectionConfig] connection config on which builder operates
    attr_reader :connection_config
    # @return [Symbol] Mechanism to rename the interface (:none -no hardware based-,
    #   :mac or :bus_id)
    attr_writer :renaming_mechanism
    # @return [Y2Network::Interface,nil] Underlying interface if it exists
    attr_reader :interface
    # @return [Boolean] True when it is a new connection
    attr_writer :newly_added

    def_delegators :@connection_config,
      :startmode, :ethtool_options, :ethtool_options=, :description, :description=

    # Constructor
    #
    # Load with reasonable defaults
    # @param type [Y2Network::InterfaceType] type of device
    # @param config [Y2Network::ConnectionConfig::Base, nil] existing configuration of device or nil
    #   for newly created
    def initialize(type:, config: nil)
      @type = type
      # TODO: also config need to store it, as newly added can be later
      # edited with option for not yet created interface
      @newly_added = config.nil?
      if config
        self.name = config.name
      else
        config = connection_config_klass(type).new
        config.propose
      end
      @connection_config = config
      @original_ip_config = ip_config_default.copy
    end

    # Sets the interface name
    #
    # It initializes the interface using the given name if it exists
    #
    # @param value [String] Interface name
    def name=(value)
      @name = value
      iface = find_interface
      self.interface = iface if iface
    end

    def newly_added?
      @newly_added
    end

    # saves builder content to backend
    def save
      @connection_config.name = name
      @connection_config.interface = name
      @connection_config.ip_aliases = aliases_to_ip_configs

      @connection_config.firewall_zone = firewall_zone
      # create new instance as name can change
      firewall_interface = Y2Firewall::Firewalld::Interface.new(name)
      if Y2Firewall::Firewalld.instance.installed? &&
          (!firewall_interface.zone || firewall_zone != firewall_interface.zone.name)
        firewall_interface.zone = firewall_zone
      end

      yast_config.rename_interface(@old_name, name, renaming_mechanism) if renamed_interface?
      yast_config.add_or_update_connection_config(@connection_config)
      # Assign the newly added interface in case of a new connection for an
      # unplugged one (bsc#1162679)
      self.interface = find_interface unless interface

      if interface.respond_to?(:custom_driver)
        interface.custom_driver = driver_auto? ? nil : driver.name
        yast_config.add_or_update_driver(driver) unless driver_auto?
      end

      nil
    end

    # Determines whether the interface has been renamed
    #
    # @return [Boolean] true if it was renamed; false otherwise
    def renamed_interface?
      return false unless interface

      name != interface.name || @renaming_mechanism != interface.renaming_mechanism
    end

    # Renames the interface
    #
    # @param new_name [String] New interface's name
    def rename_interface(new_name)
      @old_name ||= name
      @name = new_name
    end

    # Returns the current renaming mechanism
    #
    # @return [Symbol,nil] Mechanism to rename the interface (nil -no rename-, :mac or :bus_id)
    def renaming_mechanism
      @renaming_mechanism || interface.renaming_mechanism
    end

    # how many device names is proposed
    NEW_DEVICES_COUNT = 10
    # Proposes bunch of possible names for interface
    # do not modify anything
    # @return [Array<String>]
    def proposed_names
      interfaces.free_names(type.short_name, NEW_DEVICES_COUNT)
    end

    # checks if passed name is valid as interface name
    # TODO: looks sysconfig specific
    def valid_name?(name)
      !!(name =~ /^[[:alnum:]._:-]{1,15}\z/)
    end

    # checks if interface name already exists
    def name_exists?(name)
      interfaces.known_names.include?(name)
    end

    # gets valid characters that can be used in interface name
    # TODO: looks sysconfig specific
    def name_valid_characters
      Yast.import "NetworkInterfaces"

      Yast::NetworkInterfaces.ValidCharsIfcfg
    end

    # gets a list of available kernel modules for the interface
    def drivers
      return [] unless interface

      yast_config.drivers_for_interface(interface.name)
    end

    # gets currently assigned firewall zone
    def firewall_zone
      return @firewall_zone if @firewall_zone

      # TODO: handle renaming
      firewall_interface = Y2Firewall::Firewalld::Interface.new(name)
      @firewall_zone = firewall_interface.zone&.name || @connection_config.firewall_zone
    end

    # sets assigned firewall zone
    attr_writer :firewall_zone

    # @return [Y2Network::BootProtocol]
    def boot_protocol
      @connection_config.bootproto
    end

    # @param[String, Y2Network::BootProtocol]
    def boot_protocol=(value)
      value = value.name if value.is_a?(Y2Network::BootProtocol)
      @connection_config.bootproto = Y2Network::BootProtocol.from_name(value)
    end

    # @param [String,Y2Network::Startmode] name startmode name used to create Startmode object
    #   or object itself
    def startmode=(name)
      mode = name.is_a?(Startmode) ? name : Startmode.create(name)
      # assign only if it is not already this value. This helps with ordering of ifplugd_priority
      return if @connection_config.startmode && @connection_config.startmode.name == mode.name

      @connection_config.startmode = mode
    end

    # @param [Integer] value priority value
    def ifplugd_priority=(value)
      if !@connection_config.startmode || @connection_config.startmode.name != "ifplugd"
        log.info "priority set and startmode is not ifplugd. Adapting..."
        @connection_config.startmode = Startmode.create("ifplugd")
      end
      @connection_config.startmode.priority = value.to_i
    end

    # @return [Integer]
    def ifplugd_priority
      (startmode.name == "ifplugd") ? startmode.priority : 0
    end

    # gets currently assigned kernel module
    def driver
      return @driver if @driver

      if @interface&.custom_driver
        @driver = yast_config.drivers.find { |d| d.name == @interface.custom_driver }
      end
      @driver ||= :auto
    end

    # sets kernel module for interface
    # @param value [Driver]
    def driver=(value)
      @driver = value
    end

    # gets aliases for interface
    # @return [Array<Hash>] array of the connection additional IP address in
    #   hash format see #alias_for for the hash values
    def aliases
      return @aliases if @aliases

      @aliases = @connection_config.ip_aliases.map { |d| alias_for(d) }
    end

    # Convenience method to obtain a new hash from the IP additional address
    # data
    #
    # @param data [IPConfig, nil] Additional IP address configuration
    # @return [Hash<String>] hash values are `:label` for alias label,
    #   `:ip_address` for ip address, `:mask` for netmask and `:subnet_prefix` for prefix.
    def alias_for(data)
      {
        label:         data&.label.to_s,
        ip_address:    data&.address&.address.to_s,
        subnet_prefix: data&.address&.prefix ? "/#{data.address.prefix}" : "",
        id:            data&.id.to_s
      }
    end

    # sets aliases for interface
    # @param value [Array<Hash>] see #alias_for for hash values
    def aliases=(value)
      @aliases = value
    end

    # @return [String]
    def ip_address
      default = @connection_config.ip
      if default
        default.address.address.to_s
      else
        ""
      end
    end

    # @param [String] value
    def ip_address=(value)
      if value.nil? || value.empty?
        @connection_config.ip = nil
      else
        ip_config_default.address.address = value
      end
    end

    # @return [String] returns prefix or netmask. prefix in format "/<prefix>"
    def subnet_prefix
      if @connection_config.ip
        "/" + @connection_config.ip.address.prefix.to_s
      else
        ""
      end
    end

    # @param [String] value prefix or netmask is accepted. prefix in format "/<prefix>"
    def subnet_prefix=(value)
      if value.empty?
        ip_config_default.address.prefix = nil
      elsif value.start_with?("/")
        ip_config_default.address.prefix = value[1..-1].to_i
      elsif value =~ /^\d{1,3}$/
        ip_config_default.address.prefix = value.to_i
      else
        ip_config_default.address.netmask = value
      end
    end

    # @return [String]
    def hostname
      @connection_config.hostname || ""
    end

    # @param [String] value
    def hostname=(value)
      @connection_config.hostname = value
    end

    # @return [String]
    def remote_ip
      default = @connection_config.ip
      if default
        default.remote_address.to_s
      else
        ""
      end
    end

    # Sets remote ip for ptp connections
    #
    # @param [String, nil] value
    # @return [IPAddress, nil]
    def remote_ip=(value)
      return unless ip_config_default

      ip_config_default.remote_address = if value.nil? || value.empty?
        nil
      else
        IPAddress.from_string(value)
      end
    end

    # Gets Maximum Transition Unit
    # @return [String]
    def mtu
      @connection_config.mtu.to_s
    end

    # Sets Maximum Transition Unit
    # @param [String] value
    def mtu=(value)
      @connection_config.mtu = value.to_i
    end

    def configure_as_port
      self.boot_protocol = "none"
      self.aliases = []
      self.ip_address = nil
      self.subnet_prefix = ""
      self.remote_ip = ""
    end

    # @param info [Hash<String,Object>] Hardware information
    # @return [Hwinfo]
    def hwinfo_from(info)
      @hwinfo = Hwinfo.new(info)
    end

    # @return [Hwinfo]
    def hwinfo
      @hwinfo ||= Hwinfo.for(name)
    end

  private

    def ip_config_default
      return @connection_config.ip if @connection_config.ip

      @connection_config.ip = ConnectionConfig::IPConfig.new(IPAddress.from_string("0.0.0.0/32"))
    end

    # Returns the connection config class for a given type
    #
    # @param type [Y2Network::InterfaceType] type of device
    def connection_config_klass(type)
      ConnectionConfig.const_get(type.class_name)
    rescue NameError
      log.error "Could not find a class to handle '#{type.class_name}' connections"
      ConnectionConfig::Base
    end

    # Sets the interface for the builder
    #
    # @param iface [Interface] Interface to associate the builder with
    def interface=(iface)
      @renaming_mechanism ||= iface.renaming_mechanism
      @interface = iface
    end

    # Returns the underlying interface
    #
    # @return [Y2Network::Interface,nil]
    def find_interface
      return nil unless yast_config # in some tests, it could return nil

      interfaces.by_name(name)
    end

    # Returns the interfaces collection
    #
    # @return [Y2Network::InterfacesCollection]
    def interfaces
      yast_config.interfaces
    end

    # Helper method to access to the current configuration
    #
    # @return [Y2Network::Config]
    def yast_config
      Yast.import "Lan" # avoid circular dependency

      Yast::Lan.yast_config
    end

    # Determines whether the IP configuration is required
    #
    # @return [Boolean]
    def required_ip_config?
      boot_protocol == BootProtocol::STATIC
    end

    # Determines whether the driver should be set automatically
    #
    # @return [Boolean]
    def driver_auto?
      :auto == driver
    end

    # Converts aliases in hash form to a list of IPConfig objects
    #
    # @return [Array<IPConfig>]
    def aliases_to_ip_configs
      last_id = 0
      used_ids = aliases
        .select { |a| a[:id] && a[:id] =~ /\A_\d+\z/ }
        .map { |a| a[:id].sub("_", "").to_i }
      aliases.each_with_object([]) do |map, result|
        ipaddr = IPAddress.from_string(map[:ip_address])
        ipaddr.prefix = map[:subnet_prefix].delete("/").to_i if map[:subnet_prefix]
        id = map[:id]
        if id.nil? || id.empty?
          last_id = id = find_free_alias_id(used_ids, last_id) if id.nil? || id.empty?
          id = "_#{id}"
        end
        result << ConnectionConfig::IPConfig.new(ipaddr, label: map[:label], id: id)
      end
    end

    # Returns a free numeric ID for an IP aliases
    #
    # @param used_ids [Array<Integer>] Already used IDs
    # @param last_id  [Integer] Last used ID
    def find_free_alias_id(used_ids, last_id)
      loop do
        last_id += 1
        break unless used_ids.include?(last_id)
      end
      last_id
    end
  end
end
